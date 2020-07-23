;;; sharper.el --- dotnet CLI wrapper, using Transient.  -*- lexical-binding: t; -*-

;; Copyright (C) 2020 Sebastian Monia
;;
;; Author: Sebastian Monia <smonia@outlook.com>
;; URL: https://github.com/sebasmonia/sharper
;; Package-Requires: ((emacs "25") (transient "20200601"))
;; Version: 1.0
;; Keywords: maint tool

;; This file is not part of GNU Emacs.

;;; License: MIT

;;; Commentary:

;; This package aims to be a complete package for dotnet tasks that aren't part
;; of the languages but needed for any project: Solution management, nuget, etc.
;;
;; Steps to setup:
;;   1. Place sharper.el in your load-path.  Or install from MELPA.
;;   2. Add a binding to start sharper's transient:
;;       (require 'sharper)
;;       (global-set-key (kbd "C-c n") 'sharper-main-transient) ;; For "n" for "dot NET"
;;
;; For a detailed user manual see:
;; https://github.com/sebasmonia/sharper/blob/master/README.md

;;; Code:


;;------------------Package infrastructure----------------------------------------

(require 'transient)
(require 'cl-lib)
(require 'cl-extra) ;; for cl-some
(require 'project)

(defun sharper--message (text)
  "Show a TEXT as a message and log it, if 'panda-less-messages' log only."
  (message "Sharper: %s" text)
  (sharper--log "Package message:" text "\n"))

(defun sharper--log (&rest to-log)
  "Append TO-LOG to the log buffer.  Intended for internal use only."
  (let ((log-buffer (get-buffer-create "*sharper-log*"))
        (text (cl-reduce (lambda (accum elem) (concat accum " " (prin1-to-string elem t))) to-log)))
    (with-current-buffer log-buffer
      (goto-char (point-max))
      (insert text)
      (insert "\n"))))


;;------------------Customization options-----------------------------------------

(defgroup sharper nil
  "dotnet CLI wrapper, using Transient."
  :group 'extensions)

(defcustom sharper-project-extensions '("csproj" "fsproj")
  "Valid extensions for project files."
  :type 'list)

;; (defcustom panda-open-status-after-build 'ask
;;   "Open the build status for the corresponding branch after requesting a build.
;; If yes, automatically open it.  No to never ask.  Set to 'ask (default) to be prompted each time."
;;   :type '(choice (const :tag "No" nil)
;;                  (const :tag "Yes" t)
;;                  (const :tag "Ask" ask)))


;; Legend for the templates below:
;; %t = TARGET
;; %o = OPTIONS
;; %s = SOLUTION
;; %m = MS BUILD PROPERTIES (-p:Prop1=Val1 -p:Prop2=Val2 )
;; %a = RUN SETTINGS (dotnet test) or APPLICATION ARGUMENTS (dotnet run)

;; %k = PACKAGE NAME
(defvar sharper--build-template "dotnet build %t %o %m" "Template for \"dotnet build\" invocations.")
(defvar sharper--test-template "dotnet test %t %o %a" "Template for \"dotnet test\" invocations.")
(defvar sharper--clean-template "dotnet clean %t %o" "Template for \"dotnet clean\" invocations.")
(defvar sharper--publish-template "dotnet publish %t %o" "Template for \"dotnet publish\" invocations.")
(defvar sharper--pack-template "dotnet pack %t %o %m" "Template for \"dotnet pack\" invocations.")
(defvar sharper--run-template "dotnet run --project %t %o %a" "Template for \"dotnet run\" invocations.")


;; NOTE: if I start needing more than just default-dir + command I might as well create
;; a struct that has directory, command, prop1, prop2 etc.
(defvar sharper--last-build nil "A cons cell (directory . last command used for a build)")
(defvar sharper--last-test nil "A cons cell (directory . last command used to run tests)")
(defvar sharper--last-publish nil "A cons cell (directory . last command used to run a publish)")
(defvar sharper--last-pack nil "A cons cell (directory . last command used to create a NuGet package)")
(defvar sharper--last-run nil "A cons cell (directory . last command used for \"dotnet run\")")

;;------------------Main transient------------------------------------------------

(define-transient-command sharper-main-transient ()
  "dotnet Menu"
  ["Build"
   ("B" "new build" sharper-transient-build)
   ("b" "repeat last build" sharper--run-last-build)]
  ["Run test"
   ("T" "new test run" sharper-transient-test)
   ("t" "repeat last test run" sharper--run-last-test)]
  ["Run application"
   ("R" "new application run" sharper-transient-run)
   ("r" "repeat last application run" sharper--run-last-run)]
  ["Publish app"
   ("P" "new publish" sharper-transient-publish)
   ("p" "repeat last publish" sharper--run-last-publish)]
  ["Pack to .nupkg file"
   ("N" "new package" sharper-transient-pack)
   ("n" "rebuild last package" sharper--run-last-pack)]
  ["Misc commands"
   ("c" "clean" sharper-transient-clean)
   ("v" "version info (SDK & runtimes)" sharper--version-info)
   ("q" "quit" transient-quit-all)])

;; TODO: commands I haven't used and could (should?) be implemented:
;; dotnet store
;;

(defun sharper--run-last-build (&optional transient-params)
  "Run \"dotnet build\", ignore TRANSIENT-PARAMS, repeat last call via `sharper--last-build'."
  (interactive
   (list (transient-args 'sharper-transient-build)))
  (transient-set)
  (if sharper--last-build
      (let ((default-directory (car sharper--last-build))
            (command (cdr sharper--last-build)))
        (sharper--log "Compilation command\n" command "\n")
        (compile command))
    (sharper-transient-build)))

(defun sharper--run-last-test (&optional transient-params)
  "Run \"dotnet test\", ignore TRANSIENT-PARAMS, repeat last call via `sharper--last-test'."
  (interactive
   (list (transient-args 'sharper-transient-test)))
  (transient-set)
  (sharper--log "Test command\n" sharper--last-test "\n")
  (if sharper--last-test
      (let ((default-directory (car sharper--last-test))
            (command (cdr sharper--last-test)))
        (sharper--log "Test command\n" command "\n")
        (compile command))
    (sharper-transient-test)))

(defun sharper--run-last-publish (&optional transient-params)
  "Run \"dotnet publish\", ignore TRANSIENT-PARAMS, repeat last call via `sharper--last-publish'."
  (interactive
   (list (transient-args 'sharper-transient-publish)))
  (transient-set)
  (if sharper--last-publish
      (let ((default-directory (car sharper--last-publish))
            (command (cdr sharper--last-publish)))
        (sharper--log "Publish command\n" command "\n")
        (sharper--run-async-shell command "*dotnet publish*")
        (pop-to-buffer "*dotnet publish*"))
    (sharper-transient-publish)))

(defun sharper--run-last-pack (&optional transient-params)
  "Run \"dotnet build\", ignore TRANSIENT-PARAMS, repeat last call via `sharper--last-pack'."
  (interactive
   (list (transient-args 'sharper-transient-pack)))
  (transient-set)
  (if sharper--last-pack
      (let ((default-directory (car sharper--last-pack))
            (command (cdr sharper--last-pack)))
        (sharper--log "Pack command\n" command "\n")
        (compile command))
    (sharper-transient-pack)))

(defun sharper--run-last-run (&optional transient-params)
  "Run \"dotnet run\", ignore TRANSIENT-PARAMS, repeat last call via `sharper--last-run'."
  (interactive
   (list (transient-args 'sharper-transient-run)))
  (transient-set)
  (if sharper--last-run
      (let ((default-directory (car sharper--last-run))
            (command (cdr sharper--last-run)))
        (sharper--log "Run command\n" command "\n")
        (sharper--run-async-shell command "*dotnet run*")
        (pop-to-buffer "*dotnet run*"))
    (sharper-transient-run)))

(defun sharper--version-info (&optional transient-params)
  "Run \"dotnet build\", ignore TRANSIENT-PARAMS, repeat last call via `sharper--last-pack'."
  (interactive
   (list (transient-args 'sharper-main-transient)))
  (transient-set)
  (message "Compiling \"dotnet\" information...")
  (let ((dotnet-path (shell-command-to-string (if (string= system-type "windows-nt")
                                                  "where dotnet"
                                                "which dotnet")))
        (dotnet-version (shell-command-to-string "dotnet --version"))
        (dotnet-sdks (shell-command-to-string "dotnet --list-sdks"))
        (dotnet-runtimes (shell-command-to-string "dotnet --list-runtimes"))
        (buf (get-buffer-create "*dotnet info*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "dotnet path: "
              dotnet-path)
      (insert "dotnet version: "
              dotnet-version)
      (insert "\nInstalled SDKs:\n"
              dotnet-sdks)
      (insert "\nInstalled runtimes:\n"
              dotnet-runtimes)
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;;------------------Argument parsing----------------------------------------------

(defun sharper--get-target (transient-params)
  "Extract from TRANSIENT-PARAMS the \"TARGET\" argument."
  (sharper--get-argument "<TARGET>=" transient-params))

(defun sharper--get-argument (marker transient-params)
  "Extract from TRANSIENT-PARAMS the argument with  MARKER."
  (cl-some
   (lambda (an-arg) (when (string-prefix-p marker an-arg)
                      (replace-regexp-in-string marker
                                                ""
                                                an-arg)))
   transient-params))

(defun shaper--option-split-quote (an-option)
  (let* ((equal-char-index (string-match "=" an-option))
         (name (substring an-option 0 equal-char-index)))
    (if equal-char-index
        (cons name
              ;; quoting of the value for the parameter happens
              ;; later in sharper--option-alist-to-string
              (substring an-option (+ 1 equal-char-index)))
      name)))

(defun shaper--only-options (transient-params)
  "Extract from TRANSIENT-PARAMS the options (ie, start with -)."
  (mapcar #'shaper--option-split-quote
          (cl-remove-if-not (lambda (arg) (string-prefix-p "-" arg))
                            transient-params)))

(defun sharper--option-alist-to-string (options)
  "Converts the OPTIONS as parsed by `sharper--only-options' to a string."
  ;; Right now the alist intermediate step seems useless. But I think the alist
  ;; is a good idea in case we ever need to massage the parameters :)
  (mapconcat (lambda (str-or-pair)
               (if (consp str-or-pair)
                   (concat (car str-or-pair) " " (shell-quote-argument (cdr str-or-pair)))
                 str-or-pair))
             options
             " "))

(defun sharper--shell-quote-or-empty (param)
  "If PARAM nil or empty string, return empty string, else shell-quote PARAM."
  (if (or (string-empty-p param)
          (not param))
      ""
    (shell-quote-argument param)))

;;------------------dotnet common-------------------------------------------------

(defun sharper--project-root (&optional path)
  "Get the project root from optional PATH or `default-directory'."
  (project-root (project-current nil
                                 (or path
                                     default-directory))))

(defun sharper--path-directory (path)
  "Get the directory name PATH.
The only reason this is a function and not a plain call to `file-name-directory'
is because of quoted path issues on Windows."
  ;; TODO: maybe don't quote path when pulling the arg?
  ;; It works on Linux, breaks on Windows...
  ;; ALso "shell unquote" doesn't seem to be an possibility
  (when (string= system-type "windows-nt")
    (setq path (substring path 1 -1)))
  (file-name-directory path))

(defun sharper--filename-proj-or-sln-p (filename)
  "Return non-nil if FILENAME is a project or solution."
  (let ((extension (file-name-extension filename)))
    (or
     (string= "sln" extension)
     (member extension sharper-project-extensions))))

(defun sharper--filename-proj-p (filename)
  "Return non-nil if FILENAME is a project."
  (let ((extension (file-name-extension filename)))
    (member extension sharper-project-extensions)))

(defun sharper--read-solution-or-project ()
  "Offer completion for project or solution files under the current project's root."
  (let ((all-files (project-files (project-current t))))
    (completing-read "Select project or solution: "
                     all-files
                     #'sharper--filename-proj-or-sln-p)))

(defun sharper--read--project ()
  "Offer completion for project files under the current project's root."
  (let ((all-files (project-files (project-current t))))
    (completing-read "Select project or solution: "
                     all-files
                     #'sharper--filename-proj-p)))

(defun sharper--read-solution-or-project ()
  "Offer completion for project or solution files under the current project's root."
  (let ((all-files (project-files (project-current t))))
    (completing-read "Select project or solution: "
                     all-files
                     #'sharper--filename-proj-or-sln-p)))

;; TODO: it would be really nice if this validated the format
(defun sharper--read-msbuild-properties ()
  "Read name-value pairs of MSBuild property strings."
  (let ((user-input (read-string
                     "Enter the MSBuild properties in the format p1=v1 p2=v2...pN=vN: ")))
    (mapconcat
     (lambda (pair)
       (concat "-p:" pair)
       )
     (split-string user-input)
     " ")))

(define-infix-argument sharper--option-target-projsln ()
  :description "<PROJECT>|<SOLUTION>"
  :class 'transient-option
  :shortarg "T"
  :argument "<TARGET>="
  :reader (lambda (_prompt _initial-input _history)
            (sharper--read-solution-or-project)))

(define-infix-argument sharper--option-target-proj ()
  :description "<PROJECT>"
  :class 'transient-option
  :shortarg "T"
  :argument "<TARGET>="
  :reader (lambda (_prompt _initial-input _history)
            (sharper--read--project)))

(define-infix-argument sharper--option-msbuild-params ()
  :description "<MSBuildProperties>"
  :class 'transient-option
  :shortarg "-p"
  :argument "<MSBuildProperties>="
  :reader (lambda (_prompt _initial-input _history)
            (sharper--read-msbuild-properties)))

(defun sharper--run-async-shell (command buffer-name)
  "Call `async-shell-command' to run COMMAND using a buffer BUFFER-NAME."
  (let ((le-buffer (generate-new-buffer (generate-new-buffer-name
                                         buffer-name))))
    (pop-to-buffer le-buffer)
    (async-shell-command command le-buffer le-buffer)))


;;------------------dotnet build--------------------------------------------------

(defun sharper--build (&optional transient-params)
  "Run \"dotnet build\" using TRANSIENT-PARAMS as arguments & options."
  (interactive
   (list (transient-args 'sharper-transient-build)))
  (transient-set)
  (let* ((target (sharper--get-target transient-params))
         (options (shaper--only-options transient-params))
         (msbuild-props (sharper--get-argument "<MSBuildProperties>=" transient-params))
         ;; We want *compilation* to happen at the root directory
         ;; of the selected project/solution
         (directory (sharper--project-root target)))
    (unless target ;; it is possible to build without a target :shrug:
      (sharper--message "No TARGET provided, will build in default directory."))
    (let ((command (format-spec sharper--build-template
                                (format-spec-make ?t (sharper--shell-quote-or-empty target)
                                                  ?o (sharper--option-alist-to-string options)
                                                  ?m (sharper--shell-quote-or-empty  msbuild-props)))))
      (setq sharper--last-build (cons directory command))
      (sharper--run-last-build))))

(define-transient-command sharper-transient-build ()
  "dotnet build menu"
  :value '("--configuration=Debug" "--verbosity=minimal")
  ["Common Arguments"
   (sharper--option-target-projsln)
   ("-c" "Configuration" "--configuration=")
   ("-v" "Verbosity" "--verbosity=")]
  ["Other Arguments"
   ("-w" "Framework" "--framework=")
   ("-o" "Output" "--output=")
   ("-ni" "No incremental" "--no-incremental")
   ("-nd" "No dependencies" "--no-dependencies")
   ("-r" "Target runtime" "--runtime=")
   (sharper--option-msbuild-params)
   ("-s" "NuGet Package source URI" "--source")
   ("-es" "Version suffix" "--version-suffix=")]
  ["Actions"
   ("b" "build" sharper--build)
   ("q" "quit" transient-quit-all)])

;;------------------dotnet test---------------------------------------------------

(defun sharper--test (&optional transient-params)
  "Run \"dotnet test\" using TRANSIENT-PARAMS as arguments & options."
  (interactive
   (list (transient-args 'sharper-transient-test)))
  (transient-set)
  (let* ((target (sharper--get-target transient-params))
         (options (shaper--only-options transient-params))
         (run-settings (sharper--get-argument "<RunSettings>=" transient-params))
         ;; We want *compilation* to happen at the root directory
         ;; of the selected project/solution
         (directory (sharper--project-root target)))
    (unless target ;; it is possible to test without a target :shrug:
      (sharper--message "No TARGET provided, will run tests in default directory."))
    (let ((command (format-spec sharper--test-template
                                (format-spec-make ?t (sharper--shell-quote-or-empty target)
                                                  ?o (sharper--option-alist-to-string options)
                                                  ?a (if run-settings
                                                         (concat "-- " runtime-settings)
                                                       "")))))
      (setq sharper--last-test (cons directory command))
      (sharper--run-last-test))))

(define-infix-argument sharper--option-test-runsettings ()
  :description "<RunSettings>"
  :class 'transient-option
  :shortarg "RS"
  :argument "<RunSettings>="
  :reader (lambda (_prompt _initial-input _history)
            (read-string "RunSettings arguments: ")))

(define-transient-command sharper-transient-test ()
  "dotnet test menu"
  :value '("--configuration=Debug" "--verbosity=minimal")
  ["Common Arguments"
   (sharper--option-target-projsln)
   ("-c" "Configuration" "--configuration=")
   ("-v" "Verbosity" "--verbosity=")
   ("-f" "Filter" "--filter=")
   ("-l" "Logger" "--logger=")
   ("-t" "List tests discovered""--list-tests")
   ("-nb" "No build" "--no-build")]
  ["Other Arguments"
   ("-b" "Blame" "--blame")
   ("-a" "Test adapter path" "--test-adapter-path=")
   ("-w" "Framework" "--framework=")
   ("-b" "Blame" "--blame")
   ("-o" "Output" "--output=")
   ("-O" "Data collector name" "--collect")
   ("-d" "Diagnostics file" "--diag=")
   ("-nr" "No restore" "--no-restore")
   ("-r" "Target runtime" "--runtime=")
   ("-R" "Results directory" "--results-directory=")
   ("-s" "Settings" "--settings=")
   ("-es" "Version suffix" "--version-suffix=")
   (sharper--option-test-runsettings)]
  ["Actions"
   ("t" "test" sharper--test)
   ("q" "quit" transient-quit-all)])

;;------------------dotnet clean--------------------------------------------------

(defun sharper--clean (&optional transient-params)
  "Run \"dotnet clean\" using TRANSIENT-PARAMS as arguments & options."
  (interactive
   (list (transient-args 'sharper-transient-clean)))
  (transient-set)
  (let* ((target (sharper--get-target transient-params))
         (options (shaper--only-options transient-params))
         ;; We want async-shell-command to happen at the root directory
         ;; of the selected project/solution
         (default-directory (sharper--project-root target)))
    (unless target ;; it is possible to build without a target :shrug:
      (sharper--message "No TARGET provided, will run clean in default directory."))
    (let ((command (format-spec sharper--clean-template
                                (format-spec-make ?t (sharper--shell-quote-or-empty target)
                                                  ?o (sharper--option-alist-to-string options)))))
      (sharper--log "Clean command\n" command "\n")
      (sharper--run-async-shell command "*dotnet clean*"))))

(define-transient-command sharper-transient-clean ()
  "dotnet clean menu"
  :value '("--configuration=Debug" "--verbosity=normal")
  ["Common Arguments"
   (sharper--option-target-projsln)
   ("-c" "Configuration" "--configuration=")
   ("-v" "Verbosity" "--verbosity=")]
  ["Other Arguments"
   ("-w" "Framework" "--framework=")
   ("-o" "Output" "--output=")
   ("-r" "Target runtime" "--runtime=")]
  ["Actions"
   ("c" "clean" sharper--clean)
   ("q" "quit" transient-quit-all)])


;;------------------dotnet publish------------------------------------------------

(defun sharper--publish (&optional transient-params)
  "Run \"dotnet publish\" using TRANSIENT-PARAMS as arguments & options."
  (interactive
   (list (transient-args 'sharper-transient-publish)))
  (transient-set)
  (let* ((target (sharper--get-target transient-params))
         (options (shaper--only-options transient-params))
         ;; We want async-shell-command to happen at the root directory
         ;; of the selected project/solution
         (directory (sharper--project-root target)))
    (unless target ;; it is possible to test without a target :shrug:
      (sharper--message "No TARGET provided, will run tests in default directory."))
    (let ((command (format-spec sharper--publish-template
                                (format-spec-make ?t (sharper--shell-quote-or-empty target)
                                                  ?o (sharper--option-alist-to-string options)))))
      (setq sharper--last-publish (cons directory command))
      (sharper--run-last-publish))))

(define-transient-command sharper-transient-publish ()
  "dotnet publish menu"
  :value '("--configuration=Debug" "--verbosity=minimal")
  ["Common Arguments"
   (sharper--option-target-projsln)
   ("-c" "Configuration" "--configuration=")
   ("-v" "Verbosity" "--verbosity=")]
  ["Other Arguments"
   ("-f" "Force" "--force")
   ("-w" "Framework" "--framework=")
   ("-r" "Target runtime" "--runtime=")
   ("-o" "Output" "--output=")
   ;; There are somewhat odd rules governing these two
   ;; easier to include both self contained flags and
   ;; have users make sense of them
   ("-sf" "Self contained" "--self-contained")
   ("-ns" "No self contained" "--no-self-contained")
   ("-nb" "No build" "--no-build")
   ("-nd" "No dependencies" "--no-dependencies")
   ("-nr" "No restore" "--no-restore")
   ("-es" "Version suffix" "--version-suffix=")]
  ["Actions"
   ("p" "publish" sharper--publish)
   ("q" "quit" transient-quit-all)])

;;------------------dotnet pack---------------------------------------------------

(defun sharper--pack (&optional transient-params)
  "Run \"dotnet pack\" using TRANSIENT-PARAMS as arguments & options."
  (interactive
   (list (transient-args 'sharper-transient-pack)))
  (transient-set)
  (let* ((target (sharper--get-target transient-params))
         (options (shaper--only-options transient-params))
         (msbuild-props (sharper--get-argument "<MSBuildProperties>=" transient-params))
         ;; We want *compilation* to happen at the root directory
         ;; of the selected project/solution
         (directory (sharper--project-root target)))
    (unless target ;; it is possible to build without a target :shrug:
      (sharper--message "No TARGET provided, will pack in default directory."))
    (let ((command (format-spec sharper--pack-template
                                (format-spec-make ?t (sharper--shell-quote-or-empty target)
                                                  ?o (sharper--option-alist-to-string options)
                                                  ?m (sharper--shell-quote-or-empty msbuild-props)))))
      (setq sharper--last-pack (cons directory command))
      (sharper--run-last-pack))))

(define-transient-command sharper-transient-pack ()
  "dotnet build menu"
  :value '("--configuration=Debug" "--verbosity=minimal")
  ["Common Arguments"
   (sharper--option-target-projsln)
   ("-c" "Configuration" "--configuration=")
   ("-v" "Verbosity" "--verbosity=")]
  ["Other Arguments"
   ("-f" "Force" "--force")
   ("-w" "Framework" "--framework=")
   ("-r" "Target runtime" "--runtime=")
   ("-o" "Output" "--output=")
   (sharper--option-msbuild-params)
   ("-is" "Include source" "--include-source")
   ("-iy" "Include symbols" "--include-symbols")
   ("-nb" "No build" "--no-build")
   ("-nd" "No dependencies" "--no-dependencies")
   ("-nr" "No restore" "--no-restore")
   ("-s" "Serviceable" "--serviceable")
   ("-es" "Version suffix" "--version-suffix=")]
  ["Actions"
   ("p" "pack" sharper--pack)
   ("q" "quit" transient-quit-all)])

;;------------------dotnet run----------------------------------------------------

(defun sharper--run (&optional transient-params)
  "Run \"dotnet run\" using TRANSIENT-PARAMS as arguments & options."
  (interactive
   (list (transient-args 'sharper-transient-run)))
  (transient-set)
  (let* ((target (sharper--get-target transient-params))
         (options (shaper--only-options transient-params))
         (app-args (sharper--get-argument "<ApplicationArguments>=" transient-params))
         ;; For run we want this to execute in the same directory
         ;; that the project is, where the .settings file is
         (directory (sharper--path-directory target)))
    (unless target ;; it is possible to run without a target :shrug:
      (sharper--message "No TARGET provided, will run in default directory."))
    (let ((command (format-spec sharper--run-template
                                (format-spec-make ?t (sharper--shell-quote-or-empty target)
                                                  ?o (sharper--option-alist-to-string options)
                                                  ?a (if app-args
                                                         (concat "-- " app-args)
                                                       "")))))
      (setq sharper--last-run (cons directory command))
      (sharper--run-last-run))))

(define-infix-argument sharper--option-run-application-arguments ()
  :description "Application arguments"
  :class 'transient-option
  :shortarg "AA"
  :argument "<ApplicationArguments>="
  :reader (lambda (_prompt _initial-input _history)
            (read-string "Application arguments: ")))

(define-transient-command sharper-transient-run ()
  "dotnet run menu"
  :value '("--configuration=Debug" "--verbosity=minimal")
  ["Common Arguments"
   (sharper--option-target-proj)
   (sharper--option-run-application-arguments)
   ("-c" "Configuration" "--configuration=")
   ("-v" "Verbosity" "--verbosity=")]
  ["Other Arguments"
   ("-lp" "Launch profile" "--launch-profile=")
   ("-f" "Force" "--force")
   ("-w" "Framework" "--framework=")
   ("-r" "Target runtime" "--runtime=")
   ("-o" "Output" "--output=")
   ("-nl" "No launch profile" "--no-launch-profile")
   ("-nr" "No restore" "--no-restore")
   ("-nb" "No build" "--no-build")
   ("-nd" "No dependencies" "--no-dependencies")]
  ["Actions"
   ("r" "run" sharper--run)
   ("q" "quit" transient-quit-all)])

(provide 'sharper)
;;; sharper.el ends here
