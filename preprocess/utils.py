import argparse
import os
import csv
import numpy as np
from tqdm import tqdm
from nltk import word_tokenize


def phrase_process():
	f = open(os.path.join('AutoPhrase', 'models', args.dataset, 'segmentation.txt'))
	g = open(args.out_file, 'w')
	for line in tqdm(f):
		doc = ''
		temp = line.split('<phrase>')
		for seg in temp:
			temp2 = seg.split('</phrase>')
			if len(temp2) > 1:
				doc += ('_').join(temp2[0].split(' ')) + temp2[1]
			else:
				doc += temp2[0]
		g.write(doc.strip()+'\n')
	print("Phrase segmented corpus written to {}".format(args.out_file))
	return 


def preprocess():
	f = open(os.path.join(args.dataset, args.in_file))
	docs = f.readlines()
	f_out = open(args.out_file, 'w')
	for doc in tqdm(docs):
		f_out.write(' '.join([w.lower() for w in word_tokenize(doc.strip())]) + '\n')
	return 


if __name__=="__main__":
	
	parser = argparse.ArgumentParser(description='main', formatter_class=argparse.ArgumentDefaultsHelpFormatter)
	parser.add_argument('--mode', type=int)
	parser.add_argument('--dataset', default='NEW')
	parser.add_argument('--in_file', default='text.txt')
	parser.add_argument('--out_file', default='./AutoPhrase/data/text.txt')
	args = parser.parse_args()

	if args.mode == 0:
		preprocess()
	else:
		phrase_process()
	
				