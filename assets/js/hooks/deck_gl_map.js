import {Deck, OrthographicView} from "@deck.gl/core"
import {ScatterplotLayer, TextLayer} from "@deck.gl/layers"

const DeckGLMap = {
  mounted() {
    this.points = []
    this.communities = []
    this.selectedCommunity = null
    this.tooltip = null

    // Create tooltip element
    this.tooltipEl = document.createElement("div")
    this.tooltipEl.className = "deck-tooltip"
    this.tooltipEl.style.cssText =
      "position:absolute;z-index:1;pointer-events:none;background:#1f2937;" +
      "color:#f9fafb;padding:8px 12px;border-radius:6px;font-size:13px;" +
      "max-width:280px;display:none;box-shadow:0 4px 12px rgba(0,0,0,0.3);"
    this.el.appendChild(this.tooltipEl)

    // Initialize deck.gl
    this.deck = new Deck({
      parent: this.el,
      views: new OrthographicView({flipY: true}),
      initialViewState: {
        target: [0, 0, 0],
        zoom: 3,
      },
      controller: {scrollZoom: true, dragPan: true, doubleClickZoom: true},
      onViewStateChange: ({viewState}) => {
        this.deck.setProps({viewState})
      },
      getTooltip: ({object}) => null, // We handle tooltips manually
      layers: [],
    })

    // Listen for data from LiveView
    this.handleEvent("map_data", ({points, communities}) => {
      this.points = points
      this.communities = communities
      this.updateLayers()
    })

    // Listen for community selection from sidebar
    this.handleEvent("select_community", ({index}) => {
      this.selectedCommunity = index === this.selectedCommunity ? null : index
      this.updateLayers()
    })

    // Listen for fit-to-bounds
    this.handleEvent("fit_bounds", () => {
      this.fitBounds()
    })
  },

  updateLayers() {
    const selected = this.selectedCommunity
    const hasSelection = selected !== null && selected !== undefined

    const scatterLayer = new ScatterplotLayer({
      id: "users",
      data: this.points,
      getPosition: (d) => [d.x, d.y],
      getRadius: (d) => {
        if (hasSelection) {
          return d.community_index === selected ? 4 : 2
        }
        return 3
      },
      getFillColor: (d) => {
        const color = parseColor(d.color)
        if (hasSelection && d.community_index !== selected) {
          return [...color.slice(0, 3), 40] // Dim non-selected
        }
        return [...color.slice(0, 3), 200]
      },
      radiusMinPixels: 1.5,
      radiusMaxPixels: 12,
      pickable: true,
      onHover: ({object, x, y}) => {
        if (object) {
          this.tooltipEl.style.display = "block"
          this.tooltipEl.style.left = x + 12 + "px"
          this.tooltipEl.style.top = y + 12 + "px"
          this.tooltipEl.innerHTML =
            `<strong>${object.handle || object.did}</strong>` +
            (object.display_name ? `<br/>${object.display_name}` : "") +
            `<br/><span style="color:${object.color}">${object.community_label}</span>`
        } else {
          this.tooltipEl.style.display = "none"
        }
      },
      onClick: ({object}) => {
        if (object) {
          this.pushEvent("point_clicked", {
            user_id: object.user_id,
            community_index: object.community_index,
          })
        }
      },
      updateTriggers: {
        getFillColor: [selected],
        getRadius: [selected],
      },
    })

    const labelLayer = new TextLayer({
      id: "community-labels",
      data: this.communities,
      getPosition: (d) => [d.centroid_x, d.centroid_y],
      getText: (d) => d.label || `Community ${d.community_index}`,
      getSize: 14,
      getColor: (d) => {
        if (hasSelection && d.community_index !== selected) {
          return [200, 200, 200, 60]
        }
        return [255, 255, 255, 220]
      },
      fontFamily: "system-ui, -apple-system, sans-serif",
      fontWeight: "bold",
      getTextAnchor: "middle",
      getAlignmentBaseline: "center",
      background: true,
      getBackgroundColor: [0, 0, 0, 140],
      backgroundPadding: [4, 2],
      sizeMinPixels: 10,
      sizeMaxPixels: 24,
      pickable: true,
      onClick: ({object}) => {
        if (object) {
          this.pushEvent("select_community_from_map", {
            index: object.community_index,
          })
        }
      },
      updateTriggers: {
        getColor: [selected],
      },
    })

    this.deck.setProps({layers: [scatterLayer, labelLayer]})
  },

  fitBounds() {
    if (this.points.length === 0) return

    const xs = this.points.map((p) => p.x)
    const ys = this.points.map((p) => p.y)
    const minX = Math.min(...xs)
    const maxX = Math.max(...xs)
    const minY = Math.min(...ys)
    const maxY = Math.max(...ys)
    const cx = (minX + maxX) / 2
    const cy = (minY + maxY) / 2

    // Rough zoom calc based on data extent vs viewport
    const width = this.el.clientWidth
    const height = this.el.clientHeight
    const dataWidth = maxX - minX || 1
    const dataHeight = maxY - minY || 1
    const zoom = Math.log2(Math.min(width / dataWidth, height / dataHeight)) - 1

    this.deck.setProps({
      viewState: {
        target: [cx, cy, 0],
        zoom: Math.max(zoom, -2),
        transitionDuration: 500,
      },
    })
  },

  destroyed() {
    if (this.deck) {
      this.deck.finalize()
    }
  },
}

// Parse HSL or hex color to RGBA array
function parseColor(colorStr) {
  if (!colorStr) return [100, 100, 255, 200]

  const hslMatch = colorStr.match(
    /hsl\((\d+),\s*(\d+)%,\s*(\d+)%\)/
  )
  if (hslMatch) {
    const h = parseInt(hslMatch[1]) / 360
    const s = parseInt(hslMatch[2]) / 100
    const l = parseInt(hslMatch[3]) / 100
    const [r, g, b] = hslToRgb(h, s, l)
    return [r, g, b, 200]
  }

  return [100, 100, 255, 200]
}

function hslToRgb(h, s, l) {
  let r, g, b
  if (s === 0) {
    r = g = b = l
  } else {
    const hue2rgb = (p, q, t) => {
      if (t < 0) t += 1
      if (t > 1) t -= 1
      if (t < 1 / 6) return p + (q - p) * 6 * t
      if (t < 1 / 2) return q
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
      return p
    }
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s
    const p = 2 * l - q
    r = hue2rgb(p, q, h + 1 / 3)
    g = hue2rgb(p, q, h)
    b = hue2rgb(p, q, h - 1 / 3)
  }
  return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255)]
}

export default DeckGLMap
