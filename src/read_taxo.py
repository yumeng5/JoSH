import numpy as np
import pickle
import os
import argparse
from collections import defaultdict
import queue


def tree_dist(id2category, u, v): 
    visited = [0] * len(id2category)
    distance = [0] * len(id2category)
    Q = queue.Queue() 
    distance[u] = 0
    Q.put(u)  
    visited[u] = True
    while not Q.empty(): 
        x = Q.get()
        for i in id2category[x]: 
            if visited[i]: 
                continue
            distance[i] = distance[x] + 1
            Q.put(i)  
            visited[i] = 1
    return distance[v]


def read_category(file_dir):
    f = open(file_dir)
    lines = f.readlines()
    id2category = {}
    for i, line in enumerate(lines):
        line = line.strip().split(' ')
        assert int(line[0]) == i
        line = line[1:]
        id2category[i] = line
    return id2category


def read_tree(file_dir):
    f = open(file_dir)
    lines = f.readlines()
    idx = 0
    parent_map = defaultdict(list)
    children_map = defaultdict(list)
    for line in lines:
        line = line.strip().split(' ')
        assert len(line) == 2
        parent, child = line
        children_map[int(parent)].append(int(child))
        parent_map[int(child)].append(int(parent))
    return parent_map, children_map


def names2str(names):
    return '[' + ' '.join(names) + ']'


def print_taxo(id2category, children_map):
    print("Please check the following taxonomy is the correct input:")
    for i in id2category:
        if i in children_map:
            print(f"{names2str(id2category[i])}:\t" + ','.join([names2str(id2category[j]) for j in children_map[i]]))


if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='main',
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('--dataset', default='datasets/nyt')
    parser.add_argument('--category_file', default='category_names.txt')
    parser.add_argument('--taxo_file', default='taxonomy.txt')

    args = parser.parse_args()
    print(args)

    id2category = read_category(os.path.join(args.dataset, args.category_file))
    parent_map, children_map = read_tree(os.path.join(args.dataset, args.taxo_file))
    assert set(id2category.keys()) == set(parent_map.keys()).union({0})

    print_taxo(id2category, children_map)
    
    with open(os.path.join(args.dataset, 'matrix_' + args.taxo_file), 'w') as f:
        print(len(id2category), file=f)
        for i in range(len(id2category)):
            parent = parent_map[i]
            subtree = [p for p in parent]
            for p in parent:
                subtree.extend(children_map[p])
            output = np.zeros((len(id2category),), dtype=int)
            output[subtree] = 1
            output[parent] = 2
            output[i] = 0
            print('\t'.join(list(map(str, output))), file=f)
    
    with open(os.path.join(args.dataset, 'level_' + args.taxo_file), 'w') as f:
        print(len(id2category), file=f)
        for i in range(len(id2category)):
            level = 0
            visit = i
            while visit != 0:
                visit = parent_map[visit][0]
                level += 1
            print(level, file=f)
            