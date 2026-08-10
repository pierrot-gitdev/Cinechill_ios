# Règles de développement — Cinechill iOS

## Écriture des chaînes visibles

### Pas de tiret cadratin dans les textes d'interface

**Aucune chaîne affichée à l'utilisateur ne contient de `—`.** Le tiret cadratin
employé comme ponctuation est devenu la marque de fabrique des textes écrits par
une IA ; il n'a pas sa place dans le produit, quel que soit le confort qu'il
apporte à la rédaction.

Un tiret ne se supprime pas, il se **réécrit** : le retirer seul laisse une
phrase bancale. Trois traitements couvrent tous les cas rencontrés.

| Ce que le tiret portait | Traitement | Exemple, dans l'app |
|---|---|---|
| Une explication qui suit | Deux-points | `Facultatif : laissez vide pour ne rien exclure.` |
| Une seconde proposition | Une phrase de plus | `%@ l'avait déjà vu. Rien ne lui a été envoyé.` |
| Une incise au milieu | Refonte de la phrase | `Quelques questions courtes sur le temps que vous avez et l'envie du moment, puis trois films à départager.` |

En français, le deux-points prend une espace avant. En anglais, non
(`Optional: leave empty…`).

**Deux exceptions, et deux seulement :**

- Le `—` **isolé**, qui marque une valeur absente : année inconnue, film non
  noté, aucune plateforme. C'est une convention typographique de tableau, pas
  une tournure de phrase. Voir `MediaItem.displayYear`, `SwipeCard.voteAverageText`,
  `GalleryViewModel.monthTitle`.
- Le tiret demi-cadratin `–` dans une **plage numérique** : `1h30 – 2h`, `8 – 9`.

Contrôle :

```bash
grep -rn '"[^"]*—[^"]*"' $(find Cinechill_iOS -name "*.swift") | grep -v '"—"'
python3 -c "import json;d=json.load(open('Cinechill_iOS/Localizable.xcstrings'))['strings'];print([k for k in d if '—' in k])"
```

Les deux doivent rendre le vide.

### Le registre général

Les textes disent une **conséquence**, jamais un mécanisme, et jamais un
encouragement creux. « Ce qui n'est pas chez vous ne vous sera pas proposé »
plutôt que la liste des écrans qui consomment le réglage. Une ligne qui ne se
résume pas honnêtement coûte plus cher que pas de ligne du tout.

L'application parle à la première personne du pluriel indéfinie (« on cherche »,
« on vous dira »), jamais « je ».

### Vocabulaire

- **Plateforme**, jamais « abonnement », pour les services de streaming.
  « Abonnés » et « Abonnements » restent réservés au Hall, où ils désignent des
  personnes.
- Bannis de l'interface, gardés dans les commentaires de code : « séance »,
  « cadre », « cadran », « vivier », « trait ».

## Localisation

Toute chaîne visible passe par le catalogue `Cinechill_iOS/Localizable.xcstrings`
(source `fr`, traductions `en`).

- **La clé est le texte français lui-même**, pas un identifiant sémantique.
- **Tout appel porte `bundle: .app`** : `String(localized: "…", bundle: .app)` ou
  `Text("…", bundle: .app)`. Sans lui la chaîne suit la langue du système au lieu
  du sélecteur des réglages. Un littéral nu est un bug, y compris dans `Text`.
- Les API qui n'acceptent pas de bundle (`Button`, `Label`, `.alert`,
  `.accessibilityLabel/Hint/Value`) reçoivent une chaîne déjà résolue.
- `Text(verbatim:)` pour ce qui ne se traduit pas : nombres, « Cinechill »,
  `@pseudo`.
- Le catalogue s'édite **à la main** (script Python), en conservant le format
  d'Xcode : indentation de 2, séparateur `" : "`, pas de retour à la ligne final.
  Réécrire une chaîne française **renomme sa clé** : il faut alors retirer
  l'ancienne entrée et en créer une neuve, valeurs `fr` et `en` mises à jour
  ensemble.

## Jamais de `static let` pour une chaîne localisée

Une propriété statique n'est initialisée qu'une fois par processus : la chaîne y
est résolue au premier accès et n'en bouge plus. Changer de langue rebâtit bien
la hiérarchie de vues (`.id(language.selection)` à la racine), mais la mémoire
d'un `static` survit à cette reconstruction, et le texte reste dans la langue du
tout premier affichage. **Toujours une propriété calculée.** Le défaut a déjà été
corrigé sur `AppTabBar` ; ne pas le réintroduire.

## Les commits

**Une seule ligne. Pas de corps.** Le dépôt porte un historique de messages
longs ; on ne le continue pas.

- Français, verbe en tête au présent : « Ajoute », « Sort », « Relit », « Isole ».
- Une phrase, 70 caractères au plus.
- Pas de préfixe (`feat:`, `fix:`), pas d'emoji, pas de liste.
- Le *pourquoi* va dans les commentaires du code, où il reste lisible au moment
  où on modifie la ligne. Un message de commit ne se relit jamais au bon moment.

Un commit par changement réel : un sujet d'une ligne ne peut pas couvrir
honnêtement deux sujets. Séparer plutôt qu'allonger.

## Le build appartient à Pierre

Ne jamais lancer `xcodebuild` ni le simulateur. Pierre compile lui-même sur
Xcode et rapporte les erreurs.
