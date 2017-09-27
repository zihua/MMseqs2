#!/bin/sh -e
# Sequence search workflow script
fail() {
    echo "Error: $1"
    exit 1
}

notExists() {
	[ ! -f "$1" ]
}

abspath() {
    if [ -d "$1" ]; then
        (cd "$1"; pwd)
    elif [ -f "$1" ]; then
        if [[ $1 == */* ]]; then
            echo "$(cd "${1%/*}"; pwd)/${1##*/}"
        else
            echo "$(pwd)/$1"
        fi
    elif [ -d $(dirname "$1") ]; then
            echo "$(cd $(dirname "$1"); pwd)/$(basename "$1")"
    fi
}

#pre processing
[ -z "$MMSEQS" ] && echo "Please set the environment variable \$MMSEQS to your MMSEQS binary." && exit 1;
# check amount of input variables
[ "$#" -ne 4 ] && echo "Please provide <queryDB> <targetDB> <outDB> <tmp>" && exit 1;
# check if files exists
[ ! -f "$1" ] &&  echo "$1 not found!" && exit 1;
[ ! -f "$2" ] &&  echo "$2 not found!" && exit 1;
[   -f "$3" ] &&  echo "$3 exists already!" && exit 1;
[ ! -d "$4" ] &&  echo "tmp directory $4 not found!" && mkdir -p "$4";

export OMP_PROC_BIND=TRUE

INPUT="$(abspath $1)"
TARGET="$(abspath $2)"
TMP_PATH="$(abspath $4)"

SENS="$START_SENS"
while [ $SENS -le $TARGET_SENS ]; do
    # call prefilter module
    if notExists "$TMP_PATH/pref_$SENS"; then
        $RUNNER $MMSEQS prefilter "$INPUT" "$TARGET_DB_PREF" "$TMP_PATH/pref_$SENS" $PREFILTER_PAR -s $SENS \
            || fail "Prefilter died"
    fi
    # call alignment module
    if notExists "$TMP_PATH/aln_$SENS"; then
        $RUNNER $MMSEQS align "$INPUT" "$TARGET" "$TMP_PATH/pref_$SENS" "$TMP_PATH/aln_$SENS" $ALIGNMENT_PAR  \
            || fail "Alignment died"
    fi

    if [ $SENS -gt $START_SENS ]; then
        $MMSEQS mergedbs "$1" "$TMP_PATH/aln_new" "$TMP_PATH/aln_${START_SENS}" "$TMP_PATH/aln_$SENS" \
            || fail "Alignment died"
        mv -f "$TMP_PATH/aln_new" "$TMP_PATH/aln_${START_SENS}"
        mv -f "$TMP_PATH/aln_new.index" "$TMP_PATH/aln_${START_SENS}.index"
    fi

    NEXTINPUT="$TMP_PATH/input_step$SENS"
    if [  $SENS -lt $TARGET_SENS ]; then
        if notExists "$TMP_PATH/order_step$SENS"; then
            awk '$3 < 2 { print $1 }' "$TMP_PATH/aln_$SENS.index" > "$TMP_PATH/order_step$SENS" \
                || fail "Awk step $SENS died"
        fi

        if notExists "$NEXTINPUT"; then
            $MMSEQS createsubdb "$TMP_PATH/order_step$SENS" "$INPUT" "$NEXTINPUT" \
                || fail "Order step $SENS died"
        fi
    fi
    let SENS=SENS+SENS_STEP_SIZE

    INPUT=$NEXTINPUT
done

# post processing
(mv -f "$TMP_PATH/aln_${START_SENS}" "$3" && mv -f "$TMP_PATH/aln_${START_SENS}.index" "$3.index" ) \
    || fail "Could not move result to $3"

if [ -n "$REMOVE_TMP" ]; then
    echo "Remove temporary files"
    SENS=$START_SENS
    while [ $SENS -le $TARGET_SENS ]; do
        rm -f "$TMP_PATH/pref_$SENS" "$TMP_PATH/pref_$SENS.index"
        rm -f "$TMP_PATH/aln_$SENS" "$TMP_PATH/aln_$SENS.index"
        let SENS=SENS+SENS_STEP_SIZE
        NEXTINPUT="$TMP_PATH/input_step$SENS"
        rm -f "$TMP_PATH/input_step$SENS" "$TMP_PATH/input_step$SENS.index"
    done

    rm -f "$TMP_PATH/blastp.sh"
fi


