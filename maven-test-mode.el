;;; maven-test-mode.el -- Run maven tests from emacs

;; Copyright (C) 2014 Renan Ranelli <http://rranelli.com>
;; Author: Renan Ranelli
;; URL: http://github.com/rranelli/maven-test-mode
;; Created: 2014
;; Version: 0.1.2
;; Keywords: java maven test
;; Package-Requires: ((s "1.9.0"))

;; This file is NOT part of GNU Emacs.
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; See <http://www.gnu.org/licenses/> for a copy of the GNU General
;; Public License.

;;; Commentary:
;;
;; This minor mode provides some enhancements to java-mode in order to use maven
;; test tasks with little effort. It's largely based on the philosophy of
;; `rspec-mode' by Peter Williams. Namely, it provides the following
;; capabilities:
;;
;;  * toggle back and forth between a test and it's class (bound to `\C-c ,t`)
;;
;;  * verify the test class associated with the current buffer (bound to `\C-c ,v`)
;;
;;  * verify the test defined in the current buffer if it is a test file (bound
;;    to `\C-c ,v`)
;;
;;  * verify the test method defined at the point of the current buffer (bound
;;    to `\C-c ,s`)
;;
;;  * re-run the last verification process (bound to `\C-c ,r`)
;;
;;  * run tests for entire project (bound to `\C-c ,a`)
;;
;; Check the full list of available keybindings at `maven-test-mode-map'
;;
;; maven-test-mode defines a derived minor mode `maven-test-compilation' which
;; defines how to jump from compilation errors to text files.
;;
;;; Change Log:
;;
;; 0.1.2 - Add derived mode mavne-test-compilation and abolish
;; maven-test-add-regexps-for-stack-trace-jump
;; 0.1.1 - Minor changes showing surefire reports on compilation buffer
;; 0.1 - First release

;;; Code:
(require 's)
(require 'compile)

;;; Customization
;;
(defcustom maven-test-class-to-test-subs
  '(("/src/main/" . "/src/test/")
    (".java" . "Test.java"))
  "Patterns to substitute into class' filename to jump to the associated test."
  :group 'maven-test)

(defcustom maven-test-test-method-name-re
  "void \\([a-zA-Z]+\\) *() *{"
  "Pattern to identify the test method name before point"
  :group 'maven-test)

(defcustom maven-test-test-task-options
  "-q"
  "Options to add to the test task."
  :group 'maven-test)

;;; Keybindings
;;
;;;###autoload
(defvar maven-test-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd  "C-c , a") 'maven-test-all)
    (define-key map (kbd  "C-c , v") 'maven-test-file)
    (define-key map (kbd  "C-c , s") 'maven-test-method)
    (define-key map (kbd  "C-c , i") 'maven-test-install)
    (define-key map (kbd  "C-c , C") 'maven-test-clean-test-all)
    (define-key map (kbd  "C-c , r") 'recompile)
    (define-key map (kbd  "C-c , t") 'maven-test-toggle-between-test-and-class)
    (define-key map (kbd  "C-c , y") 'maven-test-toggle-between-test-and-class-other-window)
    map))

;;; Test functions
;;
(defun maven-test-all ()
  "Run maven test task."
  (interactive)
  (maven-test-compile (maven-test-all-command)))

(defun maven-test-install ()
  "Run maven build task."
  (interactive)
  (maven-test-compile (maven-test-format-task "install")))

(defun maven-test-clean-test-all ()
  "Run maven clean and test task."
  (interactive)
  (maven-test-compile (maven-test-format-task "clean test")))

(defun maven-test-file ()
  "Run maven test task for current file."
  (interactive)
  ;; HACK: this cur-file stuff is.
  (let ((cur-file (buffer-file-name)))
    (unless (maven-test-is-test-file-p)
      (maven-test-toggle-between-test-and-class))
    (maven-test-compile (maven-test-file-command))
    (find-file cur-file)))

;;; Test commands
;;
(defun maven-test-method ()
  "Run maven test task for current method"
  (interactive)
  (unless (maven-test-is-test-file-p)
    (error "Not visiting test file."))
  (maven-test-compile (maven-test-method-command)))

(defun maven-test-all-command ()
  (s-concat
   (maven-test-format-task (maven-test--test-task))
   (maven-test-format-show-surefire-reports)))

(defun maven-test-file-command ()
  (s-concat
   (maven-test-format-task (maven-test--test-task))
   (maven-test-class-name-from-buffer)
   (maven-test-format-show-surefire-reports)))

(defun maven-test-method-command ()
  (s-concat
   (maven-test-format-task (maven-test--test-task))
   (maven-test-class-name-from-buffer)
   (maven-test-get-prev-test-method-name)
   (maven-test-format-show-surefire-reports)))

;;; Command formatting
;;
(defun maven-test-format-task (task)
  (format "cd %s && mvn %s" (maven-test-root-dir) task))

(defun maven-test-format-show-surefire-reports ()
  (format
   ";EC=$?; if [[ $EC != 0 && -d %starget/surefire-reports/ ]]; then cat %starget/surefire-reports/*.txt; exit $EC; fi"
   (maven-test-root-dir)
   (maven-test-root-dir)))

(defun maven-test-class-name-from-buffer ()
  (let* ((class-file (file-name-base (buffer-file-name)))
	 (class-name (s-replace ".java" "" class-file)))
    (format " -Dtest=%s" class-name)))

(defun maven-test-get-prev-test-method-name ()
  (save-excursion
    (or
     (re-search-backward maven-test-test-method-name-re nil t)
     (error "No test method definition before point."))
    (s-concat "#" (match-string 1))))

(defun maven-test--test-task ()
  (format "test %s" maven-test-test-task-options))

;;; Toggle between test and class
;;
(defun maven-test-is-test-file-p ()
  (string-match "/src/test/" (buffer-file-name)))

(defun maven-test-toggle-between-test-and-class ()
  (interactive)
  (maven-test--toggle-between-test-and-class #'find-file))

(defun maven-test-toggle-between-test-and-class-other-window ()
  (interactive)
  (maven-test--toggle-between-test-and-class #'find-file-other-window))

(defun maven-test--toggle-between-test-and-class (func)
  (funcall func (maven-test-toggle-get-target-filename)))

(defun maven-test-toggle-get-target-filename ()
  (let* ((subs (if (maven-test-is-test-file-p)
		   (maven-test-test-to-class-subs)
		 maven-test-class-to-test-subs)))
    (s-replace-all subs (buffer-file-name))))

(defun maven-test-test-to-class-subs ()
  (mapcar
   #'(lambda (e) `(,(cdr e) . ,(car e)))
   maven-test-class-to-test-subs))

;;; Compilation mode jumps
;;
;; -- the following code was stolen from https://github.com/coreyoconnor/RCs
(defvar maven-test-java-src-dir "src/main/java/")
(defvar maven-test-java-tst-dir "src/test/java/")

(defun maven-test-java-src-stack-trace-regexp-to-filename ()
  "Generates a relative filename from java-stack-trace regexp match data."
  (maven-test--java-stack-trace-regexp-to-filename maven-test-java-src-dir))

(defun maven-test-java-tst-stack-trace-regexp-to-filename ()
  "Generates a relative filename from java-stack-trace regexp match data."
  (maven-test--java-stack-trace-regexp-to-filename maven-test-java-tst-dir))

(defun maven-test--java-stack-trace-regexp-to-filename (root)
  (concat root
	  (replace-regexp-in-string "\\." "/" (match-string 1))
	  (match-string 2)))

;;; Utilities
;;
(defun maven-test-root-dir ()
  "Locates maven root directory."
  (locate-dominating-file (buffer-file-name) "pom.xml"))

(defun maven-test-compile (command)
  (compile command  'maven-test-compilation-mode))

(define-derived-mode maven-test-compilation-mode compilation-mode "Maven Test Compilation"
  "Compilation mode for Maven output."
  (set (make-local-variable 'compilation-error-regexp-alist)
       (append '(java-tst-stack-trace java-src-stack-trace)
	       compilation-error-regexp-alist))

  (set (make-local-variable 'compilation-error-regexp-alist-alist)
       (append '((java-tst-stack-trace
		  "at \\(\\(?:[[:alnum:]]+\\.\\)+\\)+[[:alnum:]]+\\.[[:alnum:]]+(\\([[:alnum:]]+\\Test.java\\):\\([[:digit:]]+\\))$"
		  maven-test-java-tst-stack-trace-regexp-to-filename 3)
                 (java-src-stack-trace
		  "at \\(\\(?:[[:alnum:]]+\\.\\)+\\)+[[:alnum:]]+\\.[[:alnum:]]+(\\([[:alnum:]]+\\.java\\):\\([[:digit:]]+\\))$"
		  maven-test-java-src-stack-trace-regexp-to-filename 3))
               compilation-error-regexp-alist-alist)))

;;;###autoload
(define-minor-mode maven-test-mode
  "This minor mode provides utilities to run maven test tasks"
  :init-value nil
  :keymap maven-test-mode-map
  :lighter "MvnTest"
  :group 'maven-test)

(add-hook 'java-mode-hook 'maven-test-mode)

(provide 'maven-test-mode)
;;; maven-test-mode.el ends here.
