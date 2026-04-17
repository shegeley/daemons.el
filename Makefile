FILES:=daemons.el daemons-systemd.el daemons-sysvinit.el daemons-shepherd.el daemons-brew.el
VERSION:=2.1.0
PACKAGE_NAME:=daemons-$(VERSION)

all: $(PACKAGE_NAME).tar

$(PACKAGE_NAME).tar: clean $(FILES)
	mkdir $(PACKAGE_NAME)
	cp $(FILES) $(PACKAGE_NAME)
	tar -cf $(PACKAGE_NAME).tar $(PACKAGE_NAME)

guix/test:
	guix build \
	  -L . \
	  --no-grafts \
	  -e '(@ (daemons-shepherd-system-test) %test-daemons-shepherd)'

guix/build:
	guix build \
	  -L . \
	  --no-grafts \
	  -e '(@ (daemons-package) emacs-daemons-local)'

clean:
	rm -f $(PACKAGE_NAME).tar
	rm -rf $(PACKAGE_NAME)
