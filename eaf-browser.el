;;; eaf-browser.el --- Browser plugins

;; Filename: eaf-browser.el
;; Description: Browser plugins
;; Author: Andy Stewart <lazycat.manatee@gmail.com>
;; Maintainer: Andy Stewart <lazycat.manatee@gmail.com>
;; Copyright (C) 2021, Andy Stewart, all rights reserved.
;; Created: 2021-07-20 22:30:28
;; Version: 0.1
;; Last-Updated: 2021-07-20 22:30:28
;;           By: Andy Stewart
;; URL: http://www.emacswiki.org/emacs/download/eaf-browser.el
;; Keywords:
;; Compatibility: GNU Emacs 28.0.50
;;
;; Features that might be required by this library:
;;
;;
;;

;;; This file is NOT part of GNU Emacs

;;; License
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; Browser plugins
;;

;;; Installation:
;;
;; Put eaf-browser.el to your load-path.
;; The load-path is usually ~/elisp/.
;; It's set in your ~/.emacs like this:
;; (add-to-list 'load-path (expand-file-name "~/elisp"))
;;
;; And the following to your ~/.emacs startup file.
;;
;; (require 'eaf-browser)
;;
;; No need more.

;;; Customize:
;;
;;
;;
;; All of the above can customize by:
;;      M-x customize-group RET eaf-browser RET
;;

;;; Change log:
;;
;; 2021/07/20
;;      * First released.
;;

;;; Acknowledgements:
;;
;;
;;

;;; TODO
;;
;;
;;

;;; Require


;;; Code:

(defcustom eaf-browser-search-engines `(("google" . "http://www.google.com/search?ie=utf-8&oe=utf-8&q=%s")
                                        ("duckduckgo" . "https://duckduckgo.com/?q=%s"))
  "The default search engines offered by EAF.

Each element has the form (NAME . URL).
 NAME is a search engine name, as a string.
 URL pecifies the url format for the search engine.
  It should have a %s as placeholder for search string."
  :type '(alist :key-type (string :tag "Search engine name")
                :value-type (string :tag "Search engine url")))

(defcustom eaf-browser-default-search-engine "google"
  "The default search engine used by `eaf-open-browser' and `eaf-search-it'.

It must defined at `eaf-browser-search-engines'."
  :type 'string)

(defcustom eaf-browser-extension-list
  '("html" "htm")
  "The extension list of browser application."
  :type 'cons)

(defcustom eaf-browser-continue-where-left-off nil
  "Similar to Chromium's Setting -> On start-up -> Continue where you left off.

If non-nil, all active EAF Browser buffers will be saved before Emacs is killed,
and will re-open them when calling `eaf-browser-restore-buffers' in the future session."
  :type 'boolean)

(defcustom eaf-browser-fullscreen-move-cursor-corner nil
  "If non-nil, move the mouse cursor to the corner when fullscreen in the browser."
  :type 'boolean)

(defun eaf-browser-restore-buffers ()
  "EAF restore all opened EAF Browser buffers in the previous Emacs session.

This should be used after setting `eaf-browser-continue-where-left-off' to t."
  (interactive)
  (if eaf-browser-continue-where-left-off
      (let* ((browser-restore-file-path
              (concat eaf-config-location
                      (file-name-as-directory "browser")
                      (file-name-as-directory "history")
                      "restore.txt"))
             (browser-url-list
              (with-temp-buffer (insert-file-contents browser-restore-file-path)
                                (split-string (buffer-string) "\n" t))))
        (if (epc:live-p eaf-epc-process)
            (dolist (url browser-url-list)
              (eaf-open-browser url))
          (dolist (url browser-url-list)
            (push `(,url "browser" "") eaf--active-buffers))
          (when eaf--active-buffers (eaf-open-browser (nth 0 (car eaf--active-buffers))))))
    (user-error "Please set `eaf-browser-continue-where-left-off' to t first!")))

(defun eaf--browser-bookmark ()
  "Restore EAF buffer according to browser bookmark from the current file path or web URL."
  `((handler . eaf--bookmark-restore)
    (eaf-app . "browser")
    (defaults . ,(list eaf--bookmark-title))
    (filename . ,(eaf-get-path-or-url))))

(defun eaf--browser-chrome-bookmark (name url)
  "Restore EAF buffer according to chrome bookmark of given title and web URL."
  `((handler . eaf--bookmark-restore)
    (eaf-app . "browser")
    (defaults . ,(list name))
    (filename . ,url)))

(defalias 'eaf--browser-firefox-bookmark 'eaf--browser-chrome-bookmark)

(defvar eaf--firefox-bookmarks nil
  "Bookmarks that should be imported from firefox.")

(defun eaf--useful-firefox-bookmark? (uri)
  "Check whether uri is a website url."
  (or (string-prefix-p "http://" uri)
      (string-prefix-p "https://" uri)))

(defun eaf--firefox-bookmark-to-import? (title uri)
  "Check whether uri should be imported."
  (when (eaf--useful-firefox-bookmark? uri)
    (let ((old (gethash uri eaf--existing-bookmarks)))
      (when (or
             (not old)
             (and (string-equal old "") (not (string-equal title ""))))
        t))))

(defun eaf--firefox-bookmark-to-import (title uri)
  (puthash uri title eaf--existing-bookmarks)
  (add-to-list 'eaf--firefox-bookmarks (cons uri title)))

(defun eaf-import-firefox-bookmarks ()
  "Command to import firefox bookmarks."
  (interactive)
  (when (eaf-read-input "In order to import, you should first backup firefox's bookmarks to a json file. Continue?" "yes-or-no" "")
    (let ((fx-bookmark-file (read-file-name "Choose firefox bookmark file:")))
      (if (not (file-exists-p fx-bookmark-file))
          (message "Firefox bookmark file: '%s' is not exist." fx-bookmark-file)
        (setq eaf--firefox-bookmarks nil)
        (setq eaf--existing-bookmarks (eaf--load-existing-bookmarks))
        (let ((orig-bookmark-record-fn bookmark-make-record-function)
              (data (json-read-file fx-bookmark-file)))
          (cl-labels ((fn (item)
                          (pcase (alist-get 'typeCode item)
                            (1
                             (let ((title (alist-get 'title item ""))
                                   (uri (alist-get 'uri item)))
                               (when (eaf--firefox-bookmark-to-import? title uri)
                                 (eaf--firefox-bookmark-to-import title uri))))
                            (2
                             (mapc #'fn (alist-get 'children item))))))
            (fn data)
            (dolist (bm eaf--firefox-bookmarks)
              (let ((uri (car bm))
                    (title (cdr bm)))
                (setq-local bookmark-make-record-function
                            #'(lambda () (eaf--browser-firefox-bookmark title uri)))
                (bookmark-set title)))
            (setq-local bookmark-make-record-function orig-bookmark-record-fn)
            (bookmark-save)
            (message "Import success.")))))))

(defun eaf--create-new-browser-buffer (new-window-buffer-id)
  "Function for creating a new browser buffer with the specified NEW-WINDOW-BUFFER-ID."
  (let ((eaf-buffer (generate-new-buffer (concat "Browser Popup Window " new-window-buffer-id))))
    (with-current-buffer eaf-buffer
      (eaf-mode)
      (set (make-local-variable 'eaf--buffer-id) new-window-buffer-id)
      (set (make-local-variable 'eaf--buffer-url) "")
      (set (make-local-variable 'eaf--buffer-app-name) "browser"))
    (switch-to-buffer eaf-buffer)))

(defun eaf-browser--duplicate-page-in-new-tab (url)
  "Duplicate a new tab for the dedicated URL."
  (eaf-open (eaf-wrap-url url) "browser" nil t))

(defun eaf-is-valid-web-url (url)
  "Return the same URL if it is valid."
  (when (and url
             ;; URL should not include blank char.
             (< (length (split-string url)) 2)
             ;; Use regexp matching URL.
             (or (and
                  (string-prefix-p "file://" url)
                  (string-suffix-p ".html" url))
                 ;; Normal url address.
                 (string-match "^\\(https?://\\)?[a-z0-9]+\\([-.][a-z0-9]+\\)*.+\\..+[a-z0-9.]\\{1,6\\}\\(:[0-9]{1,5}\\)?\\(/.*\\)?$" url)
                 ;; Localhost url.
                 (string-match "^\\(https?://\\)?\\(localhost\\|127.0.0.1\\):[0-9]+/?" url)))
    url))

(defun eaf-wrap-url (url)
  "Wraps URL with prefix http:// if URL does not include it."
  (if (or (string-prefix-p "http://" url)
          (string-prefix-p "https://" url)
          (string-prefix-p "file://" url)
          (string-prefix-p "chrome://" url))
      url
    (concat "http://" url)))

;;;###autoload
(defun eaf-open-browser-in-background (url &optional args)
  "Open browser with the specified URL and optional ARGS in background."
  (setq eaf--monitor-configuration-p nil)
  (let ((save-buffer (current-buffer)))
    (eaf-open-browser url args)
    (switch-to-buffer save-buffer))
  (setq eaf--monitor-configuration-p t))

;;;###autoload
(defun eaf-open-browser-with-history ()
  "A wrapper around `eaf-open-browser' that provides browser history candidates.

If URL is an invalid URL, it will use `eaf-browser-default-search-engine' to search URL as string literal.

This function works best if paired with a fuzzy search package."
  (interactive)
  (let* ((browser-history-file-path
          (concat eaf-config-location
                  (file-name-as-directory "browser")
                  (file-name-as-directory "history")
                  "log.txt"))
         (history-pattern "^\\(.+\\)ᛝ\\(.+\\)ᛡ\\(.+\\)$")
         (history-file-exists (file-exists-p browser-history-file-path))
         (history (completing-read
                   "[EAF/browser] Search || URL || History: "
                   (if history-file-exists
                       (mapcar
                        (lambda (h) (when (string-match history-pattern h)
                                  (format "[%s] ⇰ %s" (match-string 1 h) (match-string 2 h))))
                        (with-temp-buffer (insert-file-contents browser-history-file-path)
                                          (split-string (buffer-string) "\n" t)))
                     nil)))
         (history-url (eaf-is-valid-web-url (when (string-match "⇰\s\\(.+\\)$" history)
                                              (match-string 1 history)))))
    (cond (history-url (eaf-open-browser history-url))
          ((eaf-is-valid-web-url history) (eaf-open-browser history))
          (t (eaf-search-it history)))))

;;;###autoload
(defun eaf-search-it (&optional search-string search-engine)
  "Use SEARCH-ENGINE search SEARCH-STRING.

If called interactively, SEARCH-STRING is defaulted to symbol or region string.
The user can enter a customized SEARCH-STRING.  SEARCH-ENGINE is defaulted
to `eaf-browser-default-search-engine' with a prefix arg, the user is able to
choose a search engine defined in `eaf-browser-search-engines'"
  (interactive)
  (let* ((real-search-engine (if current-prefix-arg
                                 (let ((all-search-engine (mapcar #'car eaf-browser-search-engines)))
                                   (completing-read
                                    (format "[EAF/browser] Select search engine (default %s): " eaf-browser-default-search-engine)
                                    all-search-engine nil t nil nil eaf-browser-default-search-engine))
                               (or search-engine eaf-browser-default-search-engine)))
         (link (or (cdr (assoc real-search-engine
                               eaf-browser-search-engines))
                   (error (format "[EAF/browser] Search engine %s is unknown to EAF!" real-search-engine))))
         (current-symbol (if mark-active
                             (if (eq major-mode 'pdf-view-mode)
                                 (progn
                                   (declare-function pdf-view-active-region-text "pdf-view.el")
                                   (car (pdf-view-active-region-text)))
                               (buffer-substring (region-beginning) (region-end)))
                           (symbol-at-point)))
         (search-url (if search-string
                         (format link search-string)
                       (let ((search-string (read-string (format "[EAF/browser] Search (%s): " current-symbol))))
                         (if (string-blank-p search-string)
                             (format link current-symbol)
                           (format link search-string))))))
    (eaf-open search-url "browser")))

(defun eaf-file-browser-qrcode (dir)
  "Open EAF File Browser application.

Select directory DIR to share file from the smartphone.

Make sure that your smartphone is connected to the same WiFi network as this computer."
  (interactive "D[EAF/file-browser] Specify Destination: ")
  (eaf-open dir "file-browser"))

(defun eaf--exit_fullscreen_request ()
  "Exit EAF browser fullscreen."
  (setq-local eaf-fullscreen-p nil)
  (eaf-monitor-configuration-change))

(defun eaf-browser-send-esc-or-exit-fullscreen ()
  "Escape fullscreen status if browser current is fullscreen.
Otherwise send key 'esc' to browser."
  (interactive)
  (if eaf-fullscreen-p
      (eaf-call-async "execute_function" eaf--buffer-id "exit_fullscreen" "<escape>")
    (eaf-call-async "send_key" eaf--buffer-id "<escape>")))

(defun eaf-browser-is-loading ()
  "Return non-nil if current page is loading."
  (interactive)
  (when (and (string= eaf--buffer-app-name "browser")
             (string= (eaf-call-sync "call_function" eaf--buffer-id "page_is_loading") "True"))))

(defun eaf--browser-export-text (buffer-name html-text)
  (let ((eaf-export-text-buffer (get-buffer-create buffer-name)))
    (with-current-buffer eaf-export-text-buffer
      (read-only-mode -1)
      (erase-buffer)
      (insert html-text)
      (goto-char (point-min))
      (read-only-mode 1))
    (switch-to-buffer eaf-export-text-buffer)
    ))

(provide 'eaf-browser)

;;; eaf-browser.el ends here