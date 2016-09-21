#!/bin/bash
# Apache Solr comes with a Standalone Java program called the SimplePostTool.
# This program is packaged into JAR and available with the installation,post.jar
BASEDIR=$(dirname $0)
POSTJAR=$BASEDIR/post.jar
URL=$KBASE_SOLR_CI/$1/update

java -Durl=$URL -Dauto=yes -Dfiletypes=json -Dcommit=yes -Dout=yes -Drecursive=yes -jar $POSTJAR $2
