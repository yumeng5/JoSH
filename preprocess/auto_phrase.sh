#!/bin/bash
# In effect, the commands below check to see if we're running in a Docker container--in that case, the (default) 
# "data" and "models" directories will have been renamed, in order to avoid conflicts with mounted directories 
# with the same names.
#
# DATA_DIR is the default directory for reading data files.  Because this directory contains not only the default
# dataset, but also language-specific files and "BAD_POS_TAGS.TXT", in most cases it's a bad idea to change it.
# However, when this script is run from a Docker container, it's perfectly fine for the user to mount an external
# directory called "data" and read the corpus from there, since the directory holding the language-specific files
# and "BAD_POS_TAGS.txt" will have been renamed to "default_data".

green=`tput setaf 2`
reset=`tput sgr0`

# dataset directory
CORPUS_DIR=../datasets/YOUR_CORPUS

# raw text file
CORPUS_FILE=text.txt

if [ ! -d "AutoPhrase" ] && [ -f "AutoPhrase.zip" ]; then
    echo "Unzipping AutoPhrase"
    unzip AutoPhrase.zip && rm AutoPhrase.zip
fi

echo ${green}===Corpus Pre-processing===${reset}
python utils.py --mode 0 --dataset ${CORPUS_DIR} --in_file ${CORPUS_FILE} --out_file ./AutoPhrase/data/text.txt

cd AutoPhrase

if [ -d "default_data" ]; then
    DATA_DIR=${DATA_DIR:- default_data}
else
    DATA_DIR=${DATA_DIR:- data}
fi
# MODEL is the directory in which the resulting model will be saved.
if [ -d "models" ]; then
    MODELS_DIR=${MODELS_DIR:- models}
else
    MODELS_DIR=${MODELS_DIR:- default_models}
fi
MODEL=${MODEL:- ${MODELS_DIR}/NEW}
# RAW_TRAIN is the input of AutoPhrase, where each line is a single document.
DEFAULT_TRAIN=${DATA_DIR}/text.txt
RAW_TRAIN=${RAW_TRAIN:- $DEFAULT_TRAIN}
# When FIRST_RUN is set to 1, AutoPhrase will run all preprocessing. 
# Otherwise, AutoPhrase directly starts from the current preprocessed data in the tmp/ folder.
FIRST_RUN=${FIRST_RUN:- 1}
# When ENABLE_POS_TAGGING is set to 1, AutoPhrase will utilize the POS tagging in the phrase mining. 
# Otherwise, a simple length penalty mode as the same as SegPhrase will be used.
ENABLE_POS_TAGGING=${ENABLE_POS_TAGGING:- 1}
# A hard threshold of raw frequency is specified for frequent phrase mining, which will generate a candidate set.
MIN_SUP=${MIN_SUP:- 10}
# You can also specify how many threads can be used for AutoPhrase
THREAD=${THREAD:- 10}
### Begin: Suggested Parameters ###
MAX_POSITIVES=-1
LABEL_METHOD=DPDN
RAW_LABEL_FILE=${RAW_LABEL_FILE:-""}
### End: Suggested Parameters ###

COMPILE=${COMPILE:- 1}
if [ $COMPILE -eq 1 ]; then
    echo ${green}===Compilation===${reset}
    bash compile.sh
fi

mkdir -p tmp
mkdir -p ${MODEL}

if [ $RAW_TRAIN == $DEFAULT_TRAIN ] && [ ! -e $DEFAULT_TRAIN ]; then
    echo ${green}===Downloading Toy Dataset===${reset}
    curl http://dmserv2.cs.illinois.edu/data/NEW.txt.gz --output ${DEFAULT_TRAIN}.gz
    gzip -d ${DEFAULT_TRAIN}.gz -f
fi

### END Compilation###

TOKENIZER="-cp .:tools/tokenizer/lib/*:tools/tokenizer/resources/:tools/tokenizer/build/ Tokenizer"
TOKEN_MAPPING=tmp/token_mapping.txt

if [ $FIRST_RUN -eq 1 ]; then
    echo ${green}===Tokenization===${reset}
    TOKENIZED_TRAIN=tmp/tokenized_train.txt
#    CASE=tmp/case_tokenized_train.txt
    echo -ne "Current step: Tokenizing input file...\033[0K\r"
    time java $TOKENIZER -m train -i $RAW_TRAIN -o $TOKENIZED_TRAIN -t $TOKEN_MAPPING -c N -thread $THREAD
fi

LANGUAGE=`cat tmp/language.txt`
LABEL_FILE=tmp/labels.txt

if [ $FIRST_RUN -eq 1 ]; then
    echo -ne "Detected Language: $LANGUAGE\033[0K\n"
    TOKENIZED_STOPWORDS=tmp/tokenized_stopwords.txt
    TOKENIZED_ALL=tmp/tokenized_all.txt
    TOKENIZED_QUALITY=tmp/tokenized_quality.txt
    STOPWORDS=$DATA_DIR/$LANGUAGE/stopwords.txt
    ALL_WIKI_ENTITIES=$DATA_DIR/$LANGUAGE/wiki_all.txt
    QUALITY_WIKI_ENTITIES=$DATA_DIR/$LANGUAGE/wiki_quality.txt
    echo -ne "Current step: Tokenizing stopword file...\033[0K\r"
    java $TOKENIZER -m test -i $STOPWORDS -o $TOKENIZED_STOPWORDS -t $TOKEN_MAPPING -c N -thread $THREAD
    echo -ne "Current step: Tokenizing wikipedia phrases...\033[0K\n"
    java $TOKENIZER -m test -i $ALL_WIKI_ENTITIES -o $TOKENIZED_ALL -t $TOKEN_MAPPING -c N -thread $THREAD
    java $TOKENIZER -m test -i $QUALITY_WIKI_ENTITIES -o $TOKENIZED_QUALITY -t $TOKEN_MAPPING -c N -thread $THREAD
fi  

### END Tokenization ###

if [[ $RAW_LABEL_FILE = *[!\ ]* ]]; then
    echo -ne "Current step: Tokenizing expert labels...\033[0K\n"
    java $TOKENIZER -m test -i $RAW_LABEL_FILE -o $LABEL_FILE -t $TOKEN_MAPPING -c N -thread $THREAD
else
    echo -ne "No provided expert labels.\033[0K\n"
fi

if [ ! $LANGUAGE == "JA" ] && [ ! $LANGUAGE == "CN" ]  && [ ! $LANGUAGE == "OTHER" ]  && [ $ENABLE_POS_TAGGING -eq 1 ] && [ $FIRST_RUN -eq 1 ]; then
    echo ${green}===Part-Of-Speech Tagging===${reset}
    RAW=tmp/raw_tokenized_train.txt
    export THREAD LANGUAGE RAW
    bash ./tools/treetagger/pos_tag.sh
    mv tmp/pos_tags.txt tmp/pos_tags_tokenized_train.txt
fi

### END Part-Of-Speech Tagging ###

echo ${green}===AutoPhrasing===${reset}

if [ $ENABLE_POS_TAGGING -eq 1 ]; then
    time ./bin/segphrase_train \
        --pos_tag \
        --thread $THREAD \
        --pos_prune $DATA_DIR/BAD_POS_TAGS.txt \
        --label_method $LABEL_METHOD \
        --label $LABEL_FILE \
        --max_positives $MAX_POSITIVES \
        --min_sup $MIN_SUP
else
    time ./bin/segphrase_train \
        --thread $THREAD \
        --label_method $LABEL_METHOD \
        --label $LABEL_FILE \
        --max_positives $MAX_POSITIVES \
        --min_sup $MIN_SUP
fi

echo ${green}===Saving Model and Results===${reset}

cp tmp/segmentation.model ${MODEL}/segmentation.model
cp tmp/token_mapping.txt ${MODEL}/token_mapping.txt
cp tmp/language.txt ${MODEL}/language.txt

### END AutoPhrasing ###

echo ${green}===Generating Output===${reset}
java $TOKENIZER -m translate -i tmp/final_quality_multi-words.txt -o ${MODEL}/AutoPhrase_multi-words.txt -t $TOKEN_MAPPING -c N -thread $THREAD
java $TOKENIZER -m translate -i tmp/final_quality_unigrams.txt -o ${MODEL}/AutoPhrase_single-word.txt -t $TOKEN_MAPPING -c N -thread $THREAD
java $TOKENIZER -m translate -i tmp/final_quality_salient.txt -o ${MODEL}/AutoPhrase.txt -t $TOKEN_MAPPING -c N -thread $THREAD

# java $TOKENIZER -m translate -i tmp/distant_training_only_salient.txt -o results/DistantTraning.txt -t $TOKEN_MAPPING -c N -thread $THREAD

### END Generating Output for Checking Quality ###

TEXT_TO_SEG=${TEXT_TO_SEG:- $DEFAULT_TRAIN}
HIGHLIGHT_MULTI=${HIGHLIGHT_MULTI:- 0.7}
HIGHLIGHT_SINGLE=${HIGHLIGHT_SINGLE:- 1.0}

SEGMENTATION_MODEL=${MODEL}/segmentation.model
TOKEN_MAPPING=${MODEL}/token_mapping.txt

ENABLE_POS_TAGGING=1
THREAD=10

green=`tput setaf 2`
reset=`tput sgr0`

### END Compilation###

echo ${green}===Tokenization===${reset}

TOKENIZER="-cp .:tools/tokenizer/lib/*:tools/tokenizer/resources/:tools/tokenizer/build/ Tokenizer"
TOKENIZED_TEXT_TO_SEG=tmp/tokenized_text_to_seg.txt
CASE=tmp/case_tokenized_text_to_seg.txt


echo -ne "Current step: Tokenizing input file...\033[0K\r"
time java $TOKENIZER -m direct_test -i $TEXT_TO_SEG -o $TOKENIZED_TEXT_TO_SEG -t $TOKEN_MAPPING -c N -thread $THREAD

LANGUAGE=`cat ${MODEL}/language.txt`
echo -ne "Detected Language: $LANGUAGE\033[0K\n"

### END Tokenization ###

echo ${green}===Part-Of-Speech Tagging===${reset}

if [ ! $LANGUAGE == "JA" ] && [ ! $LANGUAGE == "CN" ]  && [ ! $LANGUAGE == "OTHER" ]  && [ $ENABLE_POS_TAGGING -eq 1 ]; then
    RAW=tmp/raw_tokenized_text_to_seg.txt # TOKENIZED_TEXT_TO_SEG is the suffix name after "raw_"
    export THREAD LANGUAGE RAW
    bash ./tools/treetagger/pos_tag.sh
    mv tmp/pos_tags.txt tmp/pos_tags_tokenized_text_to_seg.txt
fi

POS_TAGS=tmp/pos_tags_tokenized_text_to_seg.txt

### END Part-Of-Speech Tagging ###

echo ${green}===Phrasal Segmentation===${reset}

if [ $ENABLE_POS_TAGGING -eq 1 ]; then
    time ./bin/segphrase_segment \
        --pos_tag \
        --thread $THREAD \
        --model $SEGMENTATION_MODEL \
        --highlight-multi $HIGHLIGHT_MULTI \
        --highlight-single $HIGHLIGHT_SINGLE
else
    time ./bin/segphrase_segment \
        --thread $THREAD \
        --model $SEGMENTATION_MODEL \
        --highlight-multi $HIGHLIGHT_MULTI \
        --highlight-single $HIGHLIGHT_SINGLE
fi

### END Segphrasing ###

echo ${green}===Generating Output===${reset}
java $TOKENIZER -m segmentation -i $TEXT_TO_SEG -segmented tmp/tokenized_segmented_sentences.txt -o ${MODEL}/segmentation.txt -tokenized_raw tmp/raw_tokenized_text_to_seg.txt -tokenized_id tmp/tokenized_text_to_seg.txt -c N

### END Generating Output for Checking Quality ###

echo ${green}===Segmented Corpus Post-processing===${reset}
cd ..
python utils.py --mode 1 --dataset NEW --out_file ${CORPUS_DIR}/phrase_text.txt
