html: guide.html

guide.html: guide.md
	pandoc -o $@ $<

