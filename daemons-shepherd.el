;;; daemons-shepherd.el --- UI for managing init system daemons (services) -*- lexical-binding: t -*-

;; Copyright (c) 2018 Jelle Licht <jlicht@fsfe.org>
;;
;; Author: Jelle Licht
;; URL: https://github.com/cbowdon/daemons.el
;;
;; This file is not part of GNU Emacs.
;;
;;; License: GPLv3
;;
;; Created: March 07, 2018
;; Modified: March 07, 2018
;; Version: 2.0.0
;; Keywords: unix convenience
;; Package-Requires: ((emacs "25.1"))
;;
;;; Commentary:
;; This file provides GNU Shepherd support for daemons.el.

;;; Code:
(require 'seq)
(require 'daemons)

(daemons-define-submodule daemons-shepherd
  "Daemons submodule for GNU Shepherd."

  :test (and (eq system-type 'gnu/linux)
             (executable-find "herd"))
  :commands
  '((status . (lambda (name) (format "herd status %s" name)))
    (start . (lambda (name) (format "herd start %s" name)))
    (stop . (lambda (name) (format "herd stop %s" name)))
    (restart . (lambda (name) (format "herd restart %s" name)))
    (enable . (lambda (name) (format "herd enable %s" name)))
    (disable . (lambda (name) (format "herd disable %s" name))))

  :list (daemons-shepherd--list)

  :headers [("Daemon (service)" 60 t) ("Active" 40 t)])

(defun daemons-shepherd--parse-list-item (raw-shepherd-output)
  "Parse a single line from RAW-SHEPHERD-OUTPUT into a tabulated list item."
  (let* ((parts (split-string raw-shepherd-output))
         (name (cadr parts))
         (running (car parts)))
    (list name (vector
                name
                (pcase (substring running nil 1)
                  ("+" "started")
                  ("*" "one-shot")
                  ("-" "stopped"))))))

(defun daemons-shepherd--item-is-service-p (item)
  "Non-nil if ITEM (output-line of `herd status root') describes a service."
  (string-match-p "^ [\+\-\\*] " item))

(defun daemons-shepherd--list ()
  "Return a list of daemons on a shepherd system."
  (thread-last  "herd status"
    (daemons--shell-command-to-string)
    (daemons--split-lines)
    (seq-filter 'daemons-shepherd--item-is-service-p)
    (seq-map 'daemons-shepherd--parse-list-item)))

;;; Custom actions

(defun daemons-shepherd--parse-actions (output)
  "Parse action names from herd doc OUTPUT string."
  (let (actions)
    (with-temp-buffer
      (insert output)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (when (re-search-forward "\\bactions[^:\n]*:" nil t)
          (forward-line 1)
          (while (and (not (eobp))
                      (looking-at "^[ \t]+\\([a-z_-]+\\)"))
            (push (match-string 1) actions)
            (forward-line 1)))))
    (nreverse actions)))

(defun daemons-shepherd--get-actions (name)
  "Return list of available herd actions for service NAME.
Queries `herd doc NAME' and falls back to standard actions on parse failure."
  (let* ((output (daemons--shell-command-to-string (format "herd doc %s" name)))
         (parsed (daemons-shepherd--parse-actions output)))
    (or parsed
        '("start" "stop" "status" "restart" "reload" "enable" "disable"))))

(defun daemons-shepherd-run-action (name)
  "Interactively select and run a herd action on service NAME."
  (interactive (list (daemons--daemon-at-point)))
  (let* ((actions (daemons-shepherd--get-actions name))
         (action (completing-read (format "herd action for %s: " name) actions nil nil)))
    (when (and action (not (string-empty-p action)))
      (daemons--run-shell-with-output-buffer
       (format "herd %s %s" action name)
       action
       name))))

;;; Recent messages expansion

(defun daemons-shepherd--show-messages (messages service-name)
  "Show MESSAGES from SERVICE-NAME in a dedicated buffer using `log-view-mode'."
  (let ((buf (get-buffer-create (format "*shepherd-messages: %s*" service-name))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (string-trim messages))
        (insert "\n")
        (goto-char (point-min)))
      (require 'log-view nil t)
      (if (fboundp 'log-view-mode)
          (log-view-mode)
        (view-mode 1)))
    (switch-to-buffer-other-window buf)))

(defun daemons-shepherd--buttonize-recent-messages ()
  "Make the 'Recent messages:' header in the current shepherd output clickable.
Clicking it opens the message lines in a dedicated `log-view-mode' buffer."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\s-*Recent messages:\\s-*$" nil t)
      (let* ((hdr-start (match-beginning 0))
             (hdr-end (match-end 0))
             (msgs-begin (progn (forward-line 1) (point)))
             (msgs-end (progn
                         (while (and (not (eobp))
                                     (looking-at "^[ \t]+"))
                           (forward-line 1))
                         (point)))
             (messages (buffer-substring-no-properties msgs-begin msgs-end))
             (svc daemons--current-id))
        (make-button hdr-start hdr-end
                     'action (let ((m messages) (s svc))
                               (lambda (_) (daemons-shepherd--show-messages m s)))
                     'help-echo "mouse-1, RET: open all messages in log buffer"
                     'follow-link t
                     'face '(bold underline))))))

(defun daemons-shepherd--post-process-output ()
  "Post-process shepherd output: buttonize 'Recent messages:' if present."
  (daemons-shepherd--buttonize-recent-messages))

(add-hook 'daemons-output-post-process-hook #'daemons-shepherd--post-process-output)

(provide 'daemons-shepherd)
;;; daemons-shepherd.el ends here
