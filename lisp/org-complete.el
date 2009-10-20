;;; org-complete.el --- In-buffer completion code

;; Copyright (C) 2004, 2005, 2006, 2007, 2008, 2009
;;   Free Software Foundation, Inc.
;;
;; Author: Carsten Dominik <carsten at orgmode dot org>
;;         John Wiegley <johnw at gnu dot org>
;; Keywords: outlines, hypermedia, calendar, wp
;; Homepage: http://orgmode.org
;; Version: 6.31trans
;;
;; This file is part of GNU Emacs.
;;
;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Code:

;;;; Require other packages

(eval-when-compile
  (require 'cl))

(require 'org-macs)
(require 'pcomplete)

;;;; Customization variables

(defgroup org-complete nil
  "Outline-based notes management and organizer."
  :tag "Org"
  :group 'org)

(defun org-thing-at-point ()
  "Examine the thing at point and let the caller know what it is.
The return value is a string naming the thing at point."
  (let ((beg1 (save-excursion
		(skip-chars-backward (org-re "[:alnum:]_@"))
		(point)))
	(beg (save-excursion
	       (skip-chars-backward "a-zA-Z0-9_:$")
	       (point))))
    (cond
     ((save-excursion
	(re-search-backward "^#\\+\\([A-Z_]+\\):.*"
			    (line-beginning-position) t))
      (cons "file-option" (match-string-no-properties 1)))
     ((equal (char-before beg) ?\[)
      (cons "link" nil))
     ((equal (char-before beg) ?\\)
      (cons "tex" nil))
     ((string-match "\\`\\*+[ \t]+\\'"
		    (buffer-substring (point-at-bol) beg))
      (cons "todo" nil))
     ((equal (char-before beg) ?*)
      (cons "searchhead" nil))
     ((and (equal (char-before beg1) ?:)
	   (equal (char-after (point-at-bol)) ?*))
      (cons "tag" nil))
     ((and (equal (char-before beg1) ?:)
	   (not (equal (char-after (point-at-bol)) ?*)))
      (cons "prop" nil))
     (t nil))))

(defun org-command-at-point ()
  "Return the qualified name of the Org completion entity at point.
When completing for #+STARTUP, for example, this function returns
\"file-option/STARTUP\"."
  (let ((thing (org-thing-at-point)))
    (cond
     ((string= "file-option" (car thing))
      (concat (car thing) "/" (cdr thing)))
     (t
      (car thing)))))

(defun org-parse-arguments ()
  "Parse whitespace separated arguments in the current region."
  (let ((begin (line-beginning-position))
	(end (line-end-position))
	begins args)
    (save-restriction
      (narrow-to-region begin end)
      (save-excursion
	(goto-char (point-min))
	(while (not (eobp))
	  (skip-chars-forward " \t\n[")
	  (setq begins (cons (point) begins))
	  (skip-chars-forward "^ \t\n[")
	  (setq args (cons (buffer-substring-no-properties
			    (car begins) (point))
			   args)))
	(cons (reverse args) (reverse begins))))))


(defun org-complete-initial ()
  "Calls the right completion function for first argument completions."
  (ignore
   (funcall (or (pcomplete-find-completion-function
		 (car (org-thing-at-point)))
		pcomplete-default-completion-function))))

(defun pcomplete/org-mode/file-option ()
  "Complete against all valid file options."
  (require 'org-exp)
  (pcomplete-here
   (mapcar (lambda (x)
	     (if (= ?: (aref x (1- (length x))))
		 (concat x " ")
	       x))
	   (delq nil
		 (pcomplete-uniqify-list
		  (append
		   (mapcar (lambda (x)
			     (if (string-match "^#\\+\\([A-Z_]+:?\\)" x)
				 (match-string 1 x)))
			   (org-split-string (org-get-current-options) "\n"))
		   org-additional-option-like-keywords))))
   (substring pcomplete-stub 2)))

(defun pcomplete/org-mode/file-option/STARTUP ()
  "Complete arguments for the #+STARTUP file option."
  (while (pcomplete-here
	  (let ((opts (pcomplete-uniqify-list
		       (mapcar 'car org-startup-options))))
	    ;; Some options are mutually exclusive, and shouldn't be completed
	    ;; against if certain other options have already been seen.
	    (dolist (arg pcomplete-args)
	      (cond
	       ((string= arg "hidestars")
		(setq opts (delete "showstars" opts)))))
	    opts))))

(defun pcomplete/org-mode/link ()
  "Complete against defined #+LINK patterns."
  (pcomplete-here
   (pcomplete-uniqify-list (append (mapcar 'car org-link-abbrev-alist-local)
				   (mapcar 'car org-link-abbrev-alist)))))

(defun pcomplete/org-mode/tex ()
  "Complete against TeX-style HTML entity names."
  (while (pcomplete-here
	  (pcomplete-uniqify-list (mapcar 'car org-html-entities))
	  (substring pcomplete-stub 1))))

(defun pcomplete/org-mode/todo ()
  "Complete against known TODO keywords."
  (pcomplete-here (pcomplete-uniqify-list org-todo-keywords-1)))

(defun pcomplete/org-mode/searchhead ()
  "Complete against all headings.
This needs more work, to handle headings with lots of spaces in them."
  (while
   (pcomplete-here
    (save-excursion
      (goto-char (point-min))
      (let (tbl)
	(while (re-search-forward org-todo-line-regexp nil t)
	  (push (org-make-org-heading-search-string
		 (match-string-no-properties 3) t)
		tbl))
	(pcomplete-uniqify-list tbl)))
    (substring pcomplete-stub 1))))

(defun pcomplete/org-mode/tag ()
  "Complete a tag name.  Omit tags already set."
  (while (pcomplete-here
	  (mapcar (lambda (x)
		    (concat x ":"))
		  (let ((lst (pcomplete-uniqify-list
			      (or (mapcar 'car org-tag-alist)
				  (mapcar 'car (org-get-buffer-tags))))))
		    (dolist (tag (org-get-tags))
		      (setq lst (delete tag lst)))
		    lst))
	  (and (string-match ".*:" pcomplete-stub)
	       (substring pcomplete-stub (match-end 0))))))

(defun pcomplete/org-mode/prop ()
  "Complete a property name.  Omit properties already set."
  (pcomplete-here
   (mapcar (lambda (x)
	     (concat x ": "))
	   (let ((lst (pcomplete-uniqify-list
		       (org-buffer-property-keys nil t t))))
	     (dolist (prop (org-entry-properties))
	       (setq lst (delete (car prop) lst)))
	     lst))
   (substring pcomplete-stub 1)))

;;;; Finish up

(provide 'org-complete)

;; arch-tag: 

;;; org-complete.el ends here
