CC      = gcc
# -fno-tree-slp-vectorize : voir PROFILAGE_ET_STRIP.txt (gain x5 mesuré en pré-prod)
CFLAGS  ?= -Wall -Wextra -O2 -fno-tree-slp-vectorize
LDFLAGS ?=
PREFIX  ?= $(CURDIR)/install
BINDIR   = $(PREFIX)/bin

TARGET   = tri_bulles
TESTS    = exec_tests

# Profilage (pré-prod)
DEBUG_CFLAGS = -Wall -Wextra -g -O0
RAPPORTS     = rapports
N_PROFIL    ?= 5000
N_GPROF     ?= 30000
VALGRIND     = valgrind --error-exitcode=1

.PHONY: all test install strip clean distclean debug memcheck callgrind massif gprof

all: $(TARGET)

$(TARGET): main.o tri_bulles.o
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

$(TESTS): test_tri.o tri_bulles.o
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

%.o: %.c tri.h
	$(CC) $(CFLAGS) -c $< -o $@

test: $(TESTS)
	./$(TESTS)

# Supprime la table des symboles et les infos de débogage de l'exécutable
strip:
	strip --strip-all $(TARGET)

# Pas de dépendance sur $(TARGET) : on installe l'exécutable déjà compilé
# (et strippé) sans risquer une recompilation après un make clean.
install:
	install -d $(BINDIR)
	install -m 755 $(TARGET) $(BINDIR)/$(TARGET)

# Supprime les fichiers intermédiaires mais conserve l'exécutable final
clean:
	rm -f *.o $(TESTS) gmon.out callgrind.out.* massif.out.*

# Remet le dépôt à l'état initial
distclean: clean
	rm -f $(TARGET)
	rm -rf $(CURDIR)/install $(RAPPORTS)

# ---------------------------------------------------------------- Profilage

debug:
	$(MAKE) distclean
	$(MAKE) CFLAGS="$(DEBUG_CFLAGS)" $(TARGET) $(TESTS)

$(RAPPORTS):
	mkdir -p $@

# Fuites mémoire, accès invalides, variables non initialisées
memcheck: | $(RAPPORTS)
	$(VALGRIND) --leak-check=full --show-leak-kinds=all --track-origins=yes \
		--log-file=$(RAPPORTS)/memcheck_tests.log ./$(TESTS)
	$(VALGRIND) --leak-check=full --show-leak-kinds=all --track-origins=yes \
		--log-file=$(RAPPORTS)/memcheck_app.log ./$(TARGET) -r $(N_PROFIL)

# Nombre d'instructions exécutées par fonction et par ligne de code
callgrind: | $(RAPPORTS)
	valgrind --tool=callgrind --callgrind-out-file=callgrind.out.app ./$(TARGET) -r $(N_PROFIL)
	callgrind_annotate --auto=yes callgrind.out.app > $(RAPPORTS)/callgrind.txt

# Consommation du tas dans le temps
massif: | $(RAPPORTS)
	valgrind --tool=massif --massif-out-file=massif.out.app ./$(TARGET) -r $(N_PROFIL)
	ms_print massif.out.app > $(RAPPORTS)/massif.txt

# Profil temporel par échantillonnage (recompile avec -pg)
gprof: | $(RAPPORTS)
	rm -f *.o $(TARGET)
	$(MAKE) CFLAGS="$(DEBUG_CFLAGS) -pg" LDFLAGS=-pg $(TARGET)
	./$(TARGET) -r $(N_GPROF)
	gprof -b ./$(TARGET) gmon.out > $(RAPPORTS)/gprof.txt
