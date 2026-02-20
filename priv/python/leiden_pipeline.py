"""
Community detection pipeline: Leiden + Node2Vec + UMAP + TF-IDF labeling.

Input variables (from Pythonx):
  edges: JSON string of [[source_did, target_did], ...]
  bios: JSON string of {did: bio_text, ...}
  resolution: float, Leiden resolution parameter
  n2v_dimensions: int, Node2Vec embedding dimensions

Output:
  JSON string with {communities: [...], embeddings: [...]}
"""

import json
import numpy as np

# Parse inputs from Pythonx
edge_list = json.loads(edges)
bio_map = json.loads(bios)
res = float(resolution)
dims = int(n2v_dimensions)

# Build graph with igraph
import igraph as ig

# Map DIDs to integer indices
all_dids = list(set(d for pair in edge_list for d in pair))
did_to_idx = {did: i for i, did in enumerate(all_dids)}
idx_to_did = {i: did for did, i in did_to_idx.items()}

ig_edges = [(did_to_idx[s], did_to_idx[t]) for s, t in edge_list if s in did_to_idx and t in did_to_idx]
g = ig.Graph(n=len(all_dids), edges=ig_edges, directed=True)

# Leiden community detection
import leidenalg

partition = leidenalg.find_partition(
    g,
    leidenalg.RBConfigurationVertexPartition,
    resolution_parameter=res,
)
membership = partition.membership

# Node2Vec embeddings
from node2vec import Node2Vec

# Convert to undirected for Node2Vec
g_undirected = g.to_undirected()

# node2vec needs a networkx graph
import networkx as nx

nx_graph = nx.Graph()
nx_graph.add_nodes_from(range(len(all_dids)))
nx_graph.add_edges_from([(e.source, e.target) for e in g_undirected.es])

node2vec = Node2Vec(
    nx_graph,
    dimensions=dims,
    walk_length=30,
    num_walks=200,
    workers=1,
    quiet=True,
)
model = node2vec.fit(window=10, min_count=1, batch_words=4)

# Get embedding vectors
embedding_vectors = np.array([model.wv[str(i)] for i in range(len(all_dids))])

# UMAP projection to 2D
import umap

reducer = umap.UMAP(n_components=2, random_state=42, n_neighbors=15, min_dist=0.1)
coords_2d = reducer.fit_transform(embedding_vectors)

# TF-IDF labeling per community
from sklearn.feature_extraction.text import TfidfVectorizer

community_ids = sorted(set(membership))
community_bios = {}
for cid in community_ids:
    member_dids = [idx_to_did[i] for i, m in enumerate(membership) if m == cid]
    texts = [bio_map.get(did, "") for did in member_dids]
    combined = " ".join(t for t in texts if t)
    community_bios[cid] = combined

# Generate labels from TF-IDF
all_texts = [community_bios.get(cid, "") for cid in community_ids]
non_empty = [t for t in all_texts if t.strip()]

community_labels = {}
community_top_terms = {}

if non_empty:
    vectorizer = TfidfVectorizer(max_features=1000, stop_words="english", max_df=0.8)
    try:
        tfidf_matrix = vectorizer.fit_transform(all_texts)
        feature_names = vectorizer.get_feature_names_out()

        for i, cid in enumerate(community_ids):
            scores = tfidf_matrix[i].toarray().flatten()
            top_indices = scores.argsort()[-5:][::-1]
            terms = [feature_names[j] for j in top_indices if scores[j] > 0]
            community_top_terms[cid] = terms
            community_labels[cid] = ", ".join(terms[:3]) if terms else f"Community {cid}"
    except ValueError:
        for cid in community_ids:
            community_labels[cid] = f"Community {cid}"
            community_top_terms[cid] = []
else:
    for cid in community_ids:
        community_labels[cid] = f"Community {cid}"
        community_top_terms[cid] = []

# Generate colors (HSL-based, evenly spaced hues)
n_communities = len(community_ids)
colors = {}
for i, cid in enumerate(community_ids):
    hue = int(360 * i / max(n_communities, 1))
    colors[cid] = f"hsl({hue}, 70%, 50%)"

# Compute centroids
centroids = {}
for cid in community_ids:
    member_indices = [i for i, m in enumerate(membership) if m == cid]
    if member_indices:
        cx = float(np.mean(coords_2d[member_indices, 0]))
        cy = float(np.mean(coords_2d[member_indices, 1]))
        centroids[cid] = (cx, cy)
    else:
        centroids[cid] = (0.0, 0.0)

# Build output
communities_out = []
for cid in community_ids:
    member_count = sum(1 for m in membership if m == cid)
    cx, cy = centroids[cid]
    communities_out.append({
        "index": cid,
        "label": community_labels.get(cid, f"Community {cid}"),
        "top_terms": community_top_terms.get(cid, []),
        "color": colors[cid],
        "member_count": member_count,
        "centroid_x": cx,
        "centroid_y": cy,
    })

embeddings_out = []
for i in range(len(all_dids)):
    embeddings_out.append({
        "did": idx_to_did[i],
        "x": float(coords_2d[i, 0]),
        "y": float(coords_2d[i, 1]),
        "community": membership[i],
    })

result = json.dumps({"communities": communities_out, "embeddings": embeddings_out})
