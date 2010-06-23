;;; ob-tangle.el --- Extract source code from org-mode files

;; Copyright (C) 2009 Eric Schulte

;; Author: Eric Schulte
;; Keywords: literate programming, reproducible research
;; Homepage: http://orgmode.org
;; Version: 0.01

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; Extract the code from source blocks out into raw source-code files.

;;; Code:
(require 'ob)
(require 'org-src)
(eval-when-compile
  (require 'cl))

(declare-function org-link-escape "org" (text &optional table))

(defcustom org-babel-tangle-w-comments nil
  "Control the insertion of comments into tangled code.  Non-nil
value will result in the insertion of comments for those
languages with comment support."
  :group 'org-babel-tangle
  :type 'boolean)

(defcustom org-babel-tangle-lang-exts
  '(("emacs-lisp" . "el"))
  "Alist mapping languages to their file extensions.
The key is the language name, the value is the string that should
be inserted as the extension commonly used to identify files
written in this language.  If no entry is found in this list,
then the name of the language is used."
  :group 'org-babel-tangle
  :type '(repeat
	  (cons
	   (string "Language name")
	   (string "File Extension"))))

;;;###autoload
(defun org-babel-load-file (file)
  "Load the contents of the Emacs Lisp source code blocks in the
org-mode formatted FILE.  This function will first export the
source code using `org-babel-tangle' and then load the resulting
file using `load-file'."
  (flet ((age (file)
              (float-time
               (time-subtract (current-time)
                              (nth 5 (or (file-attributes (file-truename file))
                                         (file-attributes file)))))))
    (let* ((base-name (file-name-sans-extension file))
           (exported-file (concat base-name ".el")))
      ;; tangle if the org-mode file is newer than the elisp file
      (unless (and (file-exists-p exported-file)
		   (> (age file) (age exported-file)))
        (org-babel-tangle-file file exported-file "emacs-lisp"))
      (load-file exported-file)
      (message "loaded %s" exported-file))))

;;;###autoload
(defun org-babel-tangle-file (file &optional target-file lang)
  "Extract the bodies of all source code blocks in FILE with
`org-babel-tangle'.  Optional argument TARGET-FILE can be used to
specify a default export file for all source blocks.  Optional
argument LANG can be used to limit the exported source code
blocks by language."
  (interactive "fFile to tangle: \nP")
  (let ((visited-p (get-file-buffer (expand-file-name file)))
	to-be-removed)
    (save-window-excursion
      (find-file file)
      (setq to-be-removed (current-buffer))
      (org-babel-tangle target-file lang))
    (unless visited-p
      (kill-buffer to-be-removed))))

(defun org-babel-tangle-publish (_ filename pub-dir)
  "Tangle FILENAME and place the results in PUB-DIR."
  (mapc (lambda (el) (copy-file el pub-dir t)) (org-babel-tangle-file filename)))

;;;###autoload
(defun org-babel-tangle (&optional target-file lang)
  "Extract the bodies of all source code blocks from the current
file into their own source-specific files.  Optional argument
TARGET-FILE can be used to specify a default export file for all
source blocks.  Optional argument LANG can be used to limit the
exported source code blocks by language."
  (interactive)
  (save-buffer)
  (save-excursion
    (let ((block-counter 0)
          path-collector)
      (mapc ;; map over all languages
       (lambda (by-lang)
         (let* ((lang (car by-lang))
                (specs (cdr by-lang))
		(ext (or (cdr (assoc lang org-babel-tangle-lang-exts)) lang))
                (lang-f (intern
			 (concat
			  (or (and (cdr (assoc lang org-src-lang-modes))
				   (symbol-name
				    (cdr (assoc lang org-src-lang-modes))))
			      lang)
			  "-mode")))
                she-banged)
           (mapc
            (lambda (spec)
              (flet ((get-spec (name)
                               (cdr (assoc name (nth 2 spec)))))
                (let* ((tangle (get-spec :tangle))
                       (she-bang ((lambda (sheb) (when (> (length sheb) 0) sheb))
				  (get-spec :shebang)))
                       (base-name (or (cond
                                       ((string= "yes" tangle)
                                        (file-name-sans-extension
					 (buffer-file-name)))
                                       ((string= "no" tangle) nil)
                                       ((> (length tangle) 0) tangle))
                                      target-file))
                       (file-name (when base-name
                                    ;; decide if we want to add ext to base-name
                                    (if (and ext (string= "yes" tangle))
                                        (concat base-name "." ext) base-name))))
                  (when file-name
                    ;; delete any old versions of file
                    (when (and (file-exists-p file-name)
                               (not (member file-name path-collector)))
                      (delete-file file-name))
                    ;; drop source-block to file
                    (with-temp-buffer
                      (if (fboundp lang-f) (funcall lang-f))
                      (when (and she-bang (not (member file-name she-banged)))
                        (insert (concat she-bang "\n"))
                        (setq she-banged (cons file-name she-banged)))
                      (org-babel-spec-to-string spec)
		      ;; We avoid append-to-file as it does not work with tramp.
		      (let ((content (buffer-string)))
			(with-temp-buffer
			  (if (file-exists-p file-name)
			      (insert-file-contents file-name))
			  (goto-char (point-max))
			  (insert content)
			  (write-region nil nil file-name))))
		    ;; if files contain she-bangs, then make the executable
		    (when she-bang (set-file-modes file-name ?\755))
                    ;; update counter
                    (setq block-counter (+ 1 block-counter))
                    (add-to-list 'path-collector file-name)))))
            specs)))
       (org-babel-tangle-collect-blocks lang))
      (message "tangled %d code block%s" block-counter
               (if (= block-counter 1) "" "s"))
      path-collector)))

(defun org-babel-tangle-clean ()
  "Call this function inside of a source-code file generated by
`org-babel-tangle' to remove all comments inserted automatically
by `org-babel-tangle'.  Warning, this comment removes any lines
containing constructs which resemble org-mode file links or noweb
references."
  (interactive)
  (goto-char (point-min))
  (while (or (re-search-forward "\\[\\[file:.*\\]\\[.*\\]\\]" nil t)
             (re-search-forward "<<[^[:space:]]*>>" nil t))
    (delete-region (save-excursion (beginning-of-line 1) (point))
                   (save-excursion (end-of-line 1) (forward-char 1) (point)))))

(defvar org-stored-links)
(defun org-babel-tangle-collect-blocks (&optional lang)
  "Collect all source blocks in the current org-mode file.
Return an association list of source-code block specifications of
the form used by `org-babel-spec-to-string' grouped by language.
Optional argument LANG can be used to limit the collected source
code blocks by language."
  (let ((block-counter 0) blocks)
    (org-babel-map-source-blocks (buffer-file-name)
      (setq block-counter (+ 1 block-counter))
      (let* ((link (progn (call-interactively 'org-store-link)
                          (org-babel-clean-text-properties
			   (car (pop org-stored-links)))))
             (info (org-babel-get-src-block-info))
             (source-name (intern (or (nth 4 info)
                                      (format "block-%d" block-counter))))
             (src-lang (nth 0 info))
	     (expand-cmd (intern (concat "org-babel-expand-body:" src-lang)))
             (params (nth 2 info))
             by-lang)
        (unless (string= (cdr (assoc :tangle params)) "no") ;; skip
          (unless (and lang (not (string= lang src-lang))) ;; limit by language
            ;; add the spec for this block to blocks under it's language
            (setq by-lang (cdr (assoc src-lang blocks)))
            (setq blocks (delq (assoc src-lang blocks) blocks))
            (setq blocks
                  (cons
                   (cons src-lang
                         (cons (list link source-name params
                                     ((lambda (body)
                                        (if (assoc :no-expand params)
                                            body
                                          (funcall
					   (if (fboundp expand-cmd)
					       expand-cmd
					     'org-babel-expand-body:generic)
                                           body
                                           params)))
                                      (if (and (cdr (assoc :noweb params))
                                               (string=
						"yes"
						(cdr (assoc :noweb params))))
                                          (org-babel-expand-noweb-references
					   info)
					(nth 1 info))))
                               by-lang)) blocks))))))
    ;; ensure blocks in the correct order
    (setq blocks
          (mapcar
	   (lambda (by-lang) (cons (car by-lang) (reverse (cdr by-lang))))
	   blocks))
    blocks))

(defun org-babel-spec-to-string (spec)
  "Insert the source-code specified by SPEC into the current
source code file.  This function uses `comment-region' which
assumes that the appropriate major-mode is set.  SPEC has the
form

  (link source-name params body)"
  (let ((link (nth 0 spec))
	(source-name (nth 1 spec))
	(body (nth 3 spec))
	(commentable (string= (cdr (assoc :comments (nth 2 spec))) "yes")))
    (flet ((insert-comment (text)
			   (when (and commentable
				      org-babel-tangle-w-comments)
			     (insert "\n")
			     (comment-region (point)
					     (progn (insert text) (point)))
			     (end-of-line nil)
			     (insert "\n"))))
      (insert-comment (format "[[%s][%s]]" (org-link-escape link) source-name))
      (insert (format "\n%s\n" (replace-regexp-in-string
				"^," "" (org-babel-chomp body))))
      (insert-comment (format "%s ends here" source-name)))))

(provide 'ob-tangle)
;;; ob-tangle.el ends here
