#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "tri.h"

/*
 * Usage :
 *   tri_bulles 5 2 8 1 3   -> trie les nombres passés en argument
 *   tri_bulles -r 10000    -> trie N entiers aléatoires (charge utilisée pour le profilage)
 */
int main(int argc, char *argv[]) {
    int taille;
    int *tab;
    int aleatoire = argc == 3 && strcmp(argv[1], "-r") == 0;

    if (argc < 2) {
        fprintf(stderr, "Usage : %s n1 n2 ... | -r N\n", argv[0]);
        return 1;
    }

    taille = aleatoire ? atoi(argv[2]) : argc - 1;
    if (taille <= 0) {
        fprintf(stderr, "Taille invalide\n");
        return 1;
    }

    tab = malloc(taille * sizeof(int));
    if (tab == NULL) {
        perror("malloc");
        return 1;
    }

    srand(time(NULL));
    for (int i = 0; i < taille; i++) {
        tab[i] = aleatoire ? rand() % 100000 : atoi(argv[i + 1]);
    }

    tri_bulles(tab, taille);

    if (aleatoire) {
        printf("%d entiers triés (min=%d, max=%d)\n", taille, tab[0], tab[taille - 1]);
    } else {
        for (int i = 0; i < taille; i++) {
            printf("%d ", tab[i]);
        }
        printf("\n");
    }

    free(tab);
    return 0;
}
