(load-file "./daemons-shepherd.el")
(require 'ert)

(ert-deftest shepherd-parse-list-item-test ()
  (let ((input "+ compton")
        (expected '("compton" ["compton" "started"])))
    (should (equal expected
                   (daemons-shepherd--parse-list-item input)))))

(ert-deftest shepherd-is-service-line-test ()
  (let ((input " - redshift"))
    (should (daemons-shepherd--item-is-service-p input)))
  (let ((input " + gpg-agent"))
    (should (daemons-shepherd--item-is-service-p input)))
  (let ((input "Started:"))
    (should (not (daemons-shepherd--item-is-service-p input))))
  (let ((input "Stopped:"))
    (should (not (daemons-shepherd--item-is-service-p input)))))

(ert-deftest shepherd-list-test ()
  (let* ((dummy-output "
Started:
 + compton
 + root
Stopped:
 - gpg-agent")
         (daemons--shell-command-to-string-fun (lambda (_) dummy-output))
         (expected '(("compton" ["compton" "started"])
                     ("root" ["root" "started"])
                     ("gpg-agent" ["gpg-agent" "stopped"]))))
    (should (equal expected
                   (daemons-shepherd--list)))))

(ert-deftest shepherd-parse-actions-test ()
  (let ((input "McRon.

Actions defined on mcron:
  start -- Start the service.
  stop -- Stop the service.
  schedule -- Display the job schedule.
  trigger -- Trigger immediate execution.
"))
    (should (equal '("start" "stop" "schedule" "trigger")
                   (daemons-shepherd--parse-actions input)))))

(ert-deftest shepherd-parse-actions-available-format-test ()
  "Test 'available actions:' header variant."
  (let ((input "Available actions for transmission:\n  start\n  stop\n  trigger\n"))
    (should (equal '("start" "stop" "trigger")
                   (daemons-shepherd--parse-actions input)))))

(ert-deftest shepherd-parse-actions-unrecognized-test ()
  (should (null (daemons-shepherd--parse-actions "Nothing relevant here."))))

(ert-deftest shepherd-buttonize-recent-messages-test ()
  (with-temp-buffer
    (let ((daemons--current-id "test-service"))
      (insert "Status of test-service:\n")
      (insert "  It is started.\n")
      (insert "  Recent messages:\n")
      (insert "    2024-01-01 12:00:00 service started\n")
      (insert "    2024-01-01 12:00:01 job completed\n")
      (daemons-shepherd--buttonize-recent-messages)
      (goto-char (point-min))
      (re-search-forward "Recent messages:")
      (should (button-at (match-beginning 0))))))

(ert-deftest shepherd-buttonize-recent-messages-absent-test ()
  "No error when output has no Recent messages section."
  (with-temp-buffer
    (let ((daemons--current-id "test-service"))
      (insert "Status of test-service:\n  It is stopped.\n")
      (should-not (condition-case err
                      (progn (daemons-shepherd--buttonize-recent-messages) nil)
                    (error err))))))
