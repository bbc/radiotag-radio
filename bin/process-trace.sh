#!/bin/sh
fullfile=$(readlink -f $1)
dirname=$(dirname $fullfile)
basename=$(basename $fullfile)
extension=${basename##*.}
filename=$dirname/${basename%.*}
# clear state
bin/reset-local-db.sh
if [ -e var/radio_state.json ]; then
  rm var/radio_state.json
fi
# playback recording
bin/radio --playback $filename.json --trace 2>$filename.txt
# convert to org file
ruby bin/process_playback.rb $filename.txt > $filename.org
# fix host names
sed -i 's/localhost:4568/radiotag.bbc.co.uk/g' $filename.org
sed -i 's/radiotag.prototyping.bbc.co.uk/radiotag.bbc.co.uk/g' $filename.org
sed -i 's/node1.bbcimg.co.uk\/iplayer/radiotag.bbc.co.uk/g' $filename.org
# get rid of image dimensions - should be 100x100 so don't show wrong ones!
sed -i 's/_150_84//g' $filename.org
# add setup for formatting
sed -i "1i#+SETUPFILE: ~/org/setup.org\n#+STARTUP: nohideblocks" $filename.org
# create message sequence diagram
ruby bin/org2ast.rb $filename.org | ruby bin/org-ast-to-plantuml.rb > $filename.uml
cat $filename.uml | plantuml -p > $filename.png
# extract request/response sections for narratives
ruby bin/extract-request-response.rb $filename.org
