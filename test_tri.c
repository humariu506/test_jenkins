#include <stdio.h>
#include <assert.h>

#include "tri.h"

int main() {
    int tab[] = {5, 2, 8, 1, 3};
    int attendu[] = {1, 2, 3, 5, 8};
    int taille = 5;

    tri_bulles(tab, taille);

    for (int i = 0; i < taille; i++) {
        assert(tab[i] == attendu[i]);
    }

    printf("Tous les tests sont passés avec succès !\n");
    return 0;
}