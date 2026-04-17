(define-module (daemons-shepherd-system-test)
 #:use-module ((gnu tests)          #:select (simple-operating-system
                                              marionette-operating-system
                                              system-test))
 #:use-module ((gnu system vm)      #:select (virtual-machine))
 #:use-module ((gnu services)       #:select (service))
 #:use-module ((gnu services mcron) #:select (mcron-service-type
                                              mcron-configuration))
 #:use-module ((gnu packages emacs) #:select (emacs-no-x))
 #:use-module (guix gexp)
 #:export (%test-daemons-shepherd))

;;;
;;; Daemons.el — shepherd integration system test
;;;
;;; Boots a VM with mcron, then runs Emacs --batch with daemons.el loaded to
;;; verify each new feature works against live shepherd data.
;;;
;;;   Feature 1 — daemons--buttonize-file-paths:
;;;     creates clickable buttons on absolute paths in herd status output
;;;
;;;   Feature 2 — daemons-shepherd--buttonize-recent-messages:
;;;     creates a clickable button on the "Recent messages:" header
;;;
;;;   Feature 3 — daemons-shepherd--get-actions / daemons-shepherd-run-action:
;;;     discovers real herd actions; calling them produces output
;;;

;; Elisp test scripts evaluated inside the VM via `emacs --batch --load'.
;; Each prints "PASS" or "FAIL" to stdout.

(define %feature1-test
 ;; daemons--buttonize-file-paths creates a button on an absolute path.
 (plain-file "feature1-test.el"
  "(with-temp-buffer
     (insert \"Log file: /var/log/mcron.log\\n\")
     (daemons--buttonize-file-paths)
     (goto-char (point-min))
     (re-search-forward \"/var/log/mcron.log\")
     (princ (if (button-at (match-beginning 0)) \"PASS\" \"FAIL\"))
     (terpri))"))

(define %feature2-test
 ;; daemons-shepherd--buttonize-recent-messages creates a button on the header.
 (plain-file "feature2-test.el"
  "(progn
     (setq daemons--current-id \"mcron\")
     (with-temp-buffer
       (insert \"Status of mcron:\\n\")
       (insert \"  It is started.\\n\")
       (insert \"  Recent messages:\\n\")
       (insert \"    2024-01-01 12:00:00 service started\\n\")
       (daemons-shepherd--buttonize-recent-messages)
       (goto-char (point-min))
       (re-search-forward \"Recent messages:\")
       (princ (if (button-at (match-beginning 0)) \"PASS\" \"FAIL\"))
       (terpri)))"))

(define %feature3-test
 ;; daemons-shepherd--get-actions queries live `herd doc mcron' output and
 ;; returns a non-empty list; then calling herd schedule mcron via
 ;; daemons--shell-command-to-string produces non-empty output.
 (plain-file "feature3-test.el"
  "(progn
     (setenv \"PATH\" \"/run/current-system/profile/bin\")
     ;; Part A: get-actions returns a usable list
     (let ((actions (daemons-shepherd--get-actions \"mcron\")))
       (princ (if (and (listp actions) (> (length actions) 0)) \"PASS\" \"FAIL\"))
       (terpri))
     ;; Part B: calling herd schedule mcron via the daemons shell wrapper
     ;;         produces non-empty output (proves the action runs end-to-end)
     (let ((out (daemons--shell-command-to-string \"herd schedule mcron\")))
       (princ (if (> (length (string-trim out)) 0) \"PASS\" \"FAIL\"))
       (terpri)))"))

(define %daemons-shepherd-os
 (simple-operating-system
  (service mcron-service-type
   (mcron-configuration
    (jobs (list #~(job next-second-from
                       (lambda ()
                         (call-with-output-file "/tmp/daemons-test-witness"
                           (lambda (port)
                             (display (current-time) port)))))))))))

(define (run-daemons-shepherd-test)
 (define os
  (marionette-operating-system
   %daemons-shepherd-os
   #:imported-modules '((gnu services herd)
                         (guix combinators))))

 (define vm
  (virtual-machine
   (operating-system os)
   (memory-size 768)))   ; extra headroom for emacs --batch processes

 (define test
  (with-imported-modules '((gnu build marionette))
   #~(begin
      (use-modules (srfi srfi-64)
                   (ice-9 match)
                   (gnu build marionette))

      (define marionette    (make-marionette (list #$vm)))
      (define emacs-bin     #$(file-append emacs-no-x "/bin/emacs"))
      (define daemons-el    #$(local-file "daemons.el"))
      (define dshepherd-el  #$(local-file "daemons-shepherd.el"))

      ;; Run an Elisp test script via `emacs --batch' in the VM.
      ;; Returns trimmed stdout (the script prints "PASS" or "FAIL").
      (define (emacs-test script)
       (marionette-eval
        `(begin
          (use-modules (ice-9 popen) (rnrs io ports))
          (let* ((port (open-pipe* OPEN_READ
                         ,emacs-bin "--batch"
                         "--load" ,daemons-el
                         "--load" ,dshepherd-el
                         "--load" ,script))
                 (out (get-string-all port)))
            (close-pipe port)
            (string-trim-right out)))
        marionette))

      (test-runner-current (system-test-runner #$output))
      (test-begin "daemons-shepherd")

      ;; ── Shepherd API sanity ──────────────────────────────────────────────
      ;; Stop mcron (in case it auto-started at boot) then restart it so that
      ;; start-service returns a fresh service record we can inspect.

      (test-assert "mcron service running"
       (marionette-eval
        '(begin
          (use-modules (gnu services herd))
          (false-if-exception (stop-service 'mcron))
          (define service-status (start-service 'mcron))
          service-status)
        marionette))

      (test-assert "service record has absolute log file path"
       (marionette-eval
        '(match service-status
          (#f #f)
          ((sym . rest)
           (match (assq 'log-files rest)
            (('log-files (path . _)) (string-prefix? "/" path))
            (_ #f))))
        marionette))

      (test-assert "service record has recent-messages field"
       (marionette-eval
        '(match service-status
          (#f #f)
          ((sym . rest) (pair? (assq 'recent-messages rest))))
        marionette))

      (test-assert "service record lists schedule action"
       (marionette-eval
        '(match service-status
          (#f #f)
          ((sym . rest)
           (match (assq 'actions rest)
            (('actions actions) (memq 'schedule actions))
            (_ #f))))
        marionette))

      (test-equal "schedule action callable via shepherd API"
       '(#t)
       (marionette-eval '(with-shepherd-action 'mcron ('schedule) result
                           result)
                        marionette))

      ;; ── Emacs Elisp feature tests ────────────────────────────────────────
      ;; Run daemons.el code in a real Emacs process inside the VM.

      ;; Feature 1: daemons--buttonize-file-paths
      (test-equal "daemons--buttonize-file-paths creates button on path"
       "PASS"
       (emacs-test #$%feature1-test))

      ;; Feature 2: daemons-shepherd--buttonize-recent-messages
      (test-equal "daemons-shepherd--buttonize-recent-messages creates button"
       "PASS"
       (emacs-test #$%feature2-test))

      ;; Feature 3: daemons-shepherd--get-actions + run via shell command
      ;; The test script prints two PASS/FAIL lines; both must be PASS.
      (test-equal "daemons-shepherd--get-actions and herd action execution"
       "PASS\nPASS"
       (emacs-test #$%feature3-test))

      (test-end))))
 (gexp->derivation "daemons-shepherd-test" test))

(define %test-daemons-shepherd
 (system-test
  (name "daemons-shepherd")
  (description
   "Boot a VM, run daemons.el in Emacs --batch, verify all three new features.")
  (value (run-daemons-shepherd-test))))
