PAPER = proposal
TEX = $(wildcard *.tex)
BIB = reference.bib

.PHONY: all clean graph

$(PAPER).pdf: $(TEX) $(BIB)
	mkdir -p obj
	pdflatex -output-directory obj $(PAPER)
	cp reference.bib obj
	cd obj; bibtex $(PAPER); cd ..;
	pdflatex -output-directory obj $(PAPER)
	pdflatex -output-directory obj $(PAPER)

clean:
	rm -rf obj
