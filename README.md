# Fill The Sky

Discover like-minded people on Bluesky. Fill The Sky crawls the social graph around your account, detects communities using machine learning, and renders an interactive map so you can find people who are actively posting in your interest space — not just accounts with big follower counts.

## How It Works

1. **Crawl** — Starting from a seed handle (yours), a Broadway pipeline walks the follow graph breadth-first, pulling follows and enriching profiles via the public Bluesky API.
2. **Detect** — A Python ML pipeline (called from Elixir via Pythonx) runs Leiden community detection on the follow graph, then generates 2D coordinates with Node2Vec embeddings projected through UMAP.
3. **Map** — A deck.gl scatter plot renders every user as a point, colored by community. Hover for profile cards, click to inspect, search by handle, and browse the community sidebar to explore clusters labeled by TF-IDF keywords from user bios.

The result is a zoomable constellation of your corner of Bluesky. People who follow similar accounts cluster together, so you can visually explore neighborhoods of shared interest and find new people to follow.

## Stack

| Layer | Technology |
|-------|------------|
| Web | Phoenix LiveView 1.1 |
| Data pipelines | Broadway 1.2 |
| ML | Pythonx 0.4 (Leiden, Node2Vec, UMAP, scikit-learn) |
| Visualization | deck.gl (OrthographicView + ScatterplotLayer) |
| Real-time firehose | Fresh 0.4 (Jetstream WebSocket) |
| Database | PostgreSQL with binary UUIDs |
| API | Bluesky public XRPC (no auth required) |

## Architecture

```
Bluesky Public API
       |
  Broadway Pipelines ──> PostgreSQL
  (FollowGraph + Profile)      |
       |                   Ecto Schemas
       v                   (User, Follow, CrawlSeed, CrawlCursor)
  PythonWorker GenServer         |
  (Leiden + Node2Vec + UMAP)     |
       |                         v
       └──────────────> LiveView ──> deck.gl Map
                        (MapLive, Admin pages)
```

Business logic lives in context modules (`Graph`, `Communities`, `Crawl`, `Bluesky`, `ML`), never in LiveViews. LiveViews handle only UI concerns.

## Key Design Decisions

These choices are documented in the project's [decision graph](.deciduous/) and were made for specific reasons:

- **Leiden over Louvain** — Leiden guarantees connected communities; Louvain can produce disconnected clusters that are meaningless for discovery.
- **Node2Vec + UMAP over ForceAtlas2** — ForceAtlas2 struggles above ~10K nodes. Node2Vec embeddings projected with UMAP preserve both local and global structure at scale.
- **OrthographicView over MapView** — This is relationship space, not geography. An orthographic camera lets users pan and zoom a 2D point cloud without map tile overhead.
- **Single PythonWorker GenServer** — Python's GIL means one ML job at a time anyway. A single GenServer with step-level progress reporting keeps it simple.
- **Broadway for crawling** — Back-pressure, batching, rate-limit awareness, and graceful shutdown out of the box.

## Getting Started

### Prerequisites

- Elixir 1.15+
- PostgreSQL
- Python 3.10+ (for ML pipeline: `igraph`, `leidenalg`, `node2vec`, `umap-learn`, `scikit-learn`, `numpy`)

### Setup

```bash
mix setup              # Install deps, create DB, run migrations
mix phx.server         # Start at localhost:4000
```

### Running a Crawl

1. Visit `/admin/crawl`
2. Enter a Bluesky handle as a seed (e.g. `yourhandle.bsky.social`)
3. Set crawl depth (1 = direct follows, 2 = follows-of-follows)
4. Start the crawl — progress bars update live
5. When the crawl finishes, run community detection from `/admin/pipeline`
6. Visit `/` to explore the map

## Project Status

This is an active work-in-progress. The crawl pipeline, ML community detection, and interactive map are functional. Remaining work includes follow suggestions, reply/engagement tracking, and Jetstream real-time updates.

## License

TBD
