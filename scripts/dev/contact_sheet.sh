#!/bin/sh
# Run from art_src/ingame/ux after a UX tour:  sh ../../../scripts/dev/contact_sheet.sh r5
# sheet.sh <tag> : 3-column contact sheet of art_src/ingame/ux/<tag>_*.png -> <tag>_sheet.jpg
T=$1; FILES=$(ls ${T}_[0-9]*.png); N=$(echo "$FILES" | wc -l); ARGS=""; for f in $FILES; do ARGS="$ARGS -i $f"; done
R=$(( (N + 2) / 3 )); PAD=$(( R * 3 - N ))
F=""; i=0; for f in $FILES; do F="$F[$i:v]scale=640:360[v$i];"; i=$((i+1)); done
L=""; j=0; while [ $j -lt $N ]; do L="$L[v$j]"; j=$((j+1)); done
k=0; while [ $k -lt $PAD ]; do F="$F color=black:s=640x360:d=1[p$k];"; L="$L[p$k]"; k=$((k+1)); done
TOT=$((N + PAD)); LAY=""; r=0; while [ $r -lt $R ]; do c=0; while [ $c -lt 3 ]; do LAY="$LAY${c}_${r}|"; c=$((c+1)); done; r=$((r+1)); done
# xstack layout with fixed tile size 640x360
LAY=""; r=0; while [ $r -lt $R ]; do c=0; while [ $c -lt 3 ]; do LAY="$LAY$((c*640))_$((r*360))|"; c=$((c+1)); done; r=$((r+1)); done
LAY=${LAY%|}
ffmpeg -loglevel error -y $ARGS -filter_complex "$F ${L}xstack=inputs=$TOT:layout=$LAY:fill=black" -frames:v 1 -q:v 3 ${T}_sheet.jpg
