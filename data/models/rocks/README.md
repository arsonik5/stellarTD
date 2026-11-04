# Rock models

Photogrammetry scans from Poly Haven's `moon` collection, licensed **CC0**
(public domain, no attribution required - credited here because knowing where an
asset came from matters when it needs replacing).

Source: https://polyhaven.com/models  ·  fetched at 1k texture resolution.

| file | tris | scanned size |
|---|---|---|
| moon_rock_01 | 18668 | 0.21 x 0.08 x 0.11 m |
| moon_rock_02 | 3304 | 0.25 x 0.20 x 0.25 m |
| moon_rock_03 | 5598 | 0.11 x 0.06 x 0.09 m |
| moon_rock_04 | 7636 | 0.12 x 0.05 x 0.17 m |
| moon_rock_05 | 9850 | 0.07 x 0.07 x 0.08 m |
| moon_rock_06 | 6920 | 0.09 x 0.06 x 0.09 m |
| moon_rock_07 | 6820 | 0.10 x 0.06 x 0.07 m |

`moon_rock_01` is NOT used: 18.7k triangles against 3-10k for the rest, with no
extra visible detail at boulder scale, and in a MultiMesh that cost is paid per
instance.

These are hand-sized rocks scaled up 6-20x into boulders by
`scripts/world/boulder_scatter.gd`. Texel density drops as they grow, which is
why the scale range stops where it does. If boulders need to get bigger than
about 3 m, fetch assets scanned at that size rather than scaling these further.
