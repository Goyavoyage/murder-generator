#!/usr/bin/env sh
set -e

COLOR="" # "\e[35m"
ROLOC="" # "\e[0m"

DEBUG="false"

if [ -z $1 ]
then
  CHECK="false"
else
  # The “check” command checks that the given file was not committed before use.
  if [ $1 = "check" ]
  then
    CHECK="true"
    shift
  else
    # The “checkout” command reverts back to normal any file that this script may
    # have changed, then exists.
    # It is generally a good thing to do it before committing.
    if [ $1 = "checkout" ]
    then
      git checkout dummy/murderFiles.ml dummy/usedTranslations.ml web/main.js
      exit 0
    else
      CHECK="false"
    fi
  fi
fi

if [ -z $1 ]
then
  echo "${COLOR}No argument given: compiling main.js as a default.${ROLOC}"
  TARGET=main
  JS="true"
  NATIVE="false"
  REALTARGET="main.js"
else
  REALTARGET=$1

  if [ $1 = "murderFiles.ml" ]
  then
    if [ $CHECK = "true" ]
    then
      grep '^let .* = \[\]$' dummy/murderFiles.ml && echo "${COLOR}File $1 was safe.${ROLOC}" || (echo "${COLOR}Unsafe file $1.${ROLOC}"; exit 1)
    fi

    echo "${COLOR}Creating $1 from actual content…${ROLOC}"

    # Overwriting the dummy file [dummy/murderFiles.ml] with the actual real content.
    # As this overwrites a committed file, please only do that on deployment.
    echo "let files = [\n`ls data/*.murder | sed -e 's/\\(.*\\)/    \"\\1\" ;/'`\n  ]" > dummy/murderFiles.ml

    echo "${COLOR}Done.${ROLOC}"
    exit 0
  fi

  if [ $1 = "usedTranslations.ml" ]
  then
    if [ $CHECK = "true" ]
    then
      grep '^let .* = \[\]$' dummy/usedTranslations.ml && echo "${COLOR}File $1 was safe.${ROLOC}" || (echo "${COLOR}Unsafe file $1.${ROLOC}"; exit 1)
    fi

    echo "${COLOR}Creating $1 from actual content…${ROLOC}"

    # Overwriting the dummy file [dummy/usedTranslations.ml] with the actually
    # used translations.
    # As this overwrites a committed file, please only do that on deployment.
    echo "let used = [\n`grep -o 'get_translation \"[^\"]*\"' src/main.ml | sed -e 's/get_translation \\(\"[^\"]*\"\\)/    \\1 ;/'`\n  ]" > dummy/usedTranslations.ml

    echo "${COLOR}Done.${ROLOC}"
    exit 0
  fi

  TARGET=`echo "$1" | sed -e 's/\\..*//'`

  if expr match "$1" ".*\.js" > /dev/null
  then
    JS="true"
    NATIVE="false"
  else
    JS="false"
    if expr match "$1" ".*\.native" > /dev/null
    then
      NATIVE="true"
    else
      NATIVE="false"
    fi
  fi
fi

if [ $NATIVE = "true" ]
then
  EXT="native"
else
  EXT="byte"
fi

if [ $TARGET = "main" ]
then
  if [ $JS = "true" ]
  then
    TARGET="main_js"
  else
    if [ $NATIVE = "true" ]
    then
      TARGET="main_native"
    fi
  fi
fi

if [ $DEBUG = "true" ]
then
  DEBUGFLAG=",debug"
else
  DEBUGFLAG=""
fi

if [ $JS = "true" ]
then
  ADDITIONALPACKAGES=",js_of_ocaml,js_of_ocaml-lwt,js_of_ocaml-ppx,js_of_ocaml-ppx.deriving,js_of_ocaml.deriving"
  ADDITIONALFLAGS=""
else
  ADDITIONALPACKAGES=",lwt.unix"
  ADDITIONALFLAGS=",thread"
fi

# Compile to bytecode
echo "${COLOR}Compiling to bytecode as ${TARGET}.${EXT}…${ROLOC}"
ocamlbuild -use-ocamlfind -Is src,lib,dummy \
           -pkgs unix,extlib,yojson,lwt,lwt_ppx,ppx_deriving${ADDITIONALPACKAGES} \
           -use-menhir -menhir "menhir --explain" \
           -tags "optimize(3)${DEBUGFLAG}${ADDITIONALFLAGS}" \
           $TARGET.$EXT
echo "${COLOR}Done.${ROLOC}"

REALTARGETBASE=`echo "$REALTARGET" | sed -e 's/\\..*//'`
if [ $TARGET.$EXT != $REALTARGETBASE ]
then
  echo "${COLOR}Moving file from ${TARGET}.${EXT} to ${REALTARGETBASE}.${EXT}.${ROLOC}"
  mv -f $TARGET.$EXT $REALTARGETBASE.$EXT
  TARGET=$REALTARGETBASE
fi

if [ $JS = "true" ]
then

  if [ $CHECK = "true" ]
  then
    grep '^throw .* has not been compiled.*dummy.*$' web/main.js && echo "${COLOR}File main.js was safe.${ROLOC}" || (echo "${COLOR}Unsafe file main.js.${ROLOC}"; exit 1)
  fi

  if [ $DEBUG = "true" ]
  then
    DEBUGFLAG="--pretty"
  else
    DEBUGFLAG=""
  fi

  echo "${COLOR}Compiling to JavaScript as ${TARGET}.js…${ROLOC}"

  # Translate to JavaScript
  js_of_ocaml $DEBUGFLAG $TARGET.byte

  # Adding license information.
  sed -i "1i/* The source code of this compiled program is available at https://github.com/Mbodin/murder-generator */" $TARGET.js
  sed -i "1i/* @license magnet:?xt=urn:btih:1f739d935676111cfff4b4693e3816e664797050&dn=gpl-3.0.txt GPL-v3-or-Later */" $TARGET.js
  echo "/* @license-end */" >> $TARGET.js
  echo "//# sourceURL=main.js" >> $TARGET.js

  echo "${COLOR}Done.${ROLOC}"
fi

