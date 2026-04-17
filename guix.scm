(use-modules
 ((gnu packages emacs-xyz) #:select (emacs-daemons))
 (guix packages)
 (guix gexp))

(package
  (inherit emacs-daemons)
  (version "dev")
  (source (local-file "." "daemons.el-checkout"
                      #:recursive? #t
                      #:select? (lambda (file stat)
                                  (or (string-suffix? ".el" file)
                                      (string=? (basename file) "."))))))
