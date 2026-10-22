import { useEffect, useRef, useState } from "react";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import type { Field, Observation } from "@agromax/contracts";
export function FieldMap({
  fields,
  selected,
  onSelect,
  observations = [],
  onObservation,
}: {
  fields: Field[];
  selected: string;
  onSelect: (id: string) => void;
  observations?: Observation[];
  onObservation?: (o: Observation) => void;
}) {
  const [basemap, setBasemap] = useState<"scheme" | "satellite">("satellite");
  const [tileError, setTileError] = useState("");
  const el = useRef<HTMLDivElement>(null);
  const map = useRef<L.Map | null>(null);
  const layers = useRef<L.LayerGroup | null>(null);
  useEffect(() => {
    if (!el.current) return;
    const m = L.map(el.current, { zoomControl: true }).setView([55.7, 37.6], 9);
    map.current = m;
    layers.current = L.layerGroup().addTo(m);
    const obs = new ResizeObserver(() => m.invalidateSize());
    obs.observe(el.current);
    return () => {
      obs.disconnect();
      m.remove();
      map.current = null;
    };
  }, []);
  useEffect(() => {
    const m = map.current;
    if (!m) return;
    let active = true;
    const satellite = basemap === "satellite";
    const tileLayer = L.tileLayer(
      satellite
        ? "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
        : "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
      {
        attribution: satellite
          ? 'Source: <a href="https://www.esri.com/">Esri</a>, Vantor, Earthstar Geographics, and the GIS User Community'
          : '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
        maxZoom: 19,
      },
    );
    tileLayer.on("tileerror", () => {
      if (!active) return;
      if (satellite) {
        setTileError("Спутниковые снимки недоступны. Открыта схема OpenStreetMap.");
        setBasemap("scheme");
      } else {
        setTileError("Схема карты недоступна. Контуры и список полей доступны.");
      }
    });
    tileLayer.addTo(m);
    return () => {
      active = false;
      tileLayer.remove();
    };
  }, [basemap]);
  useEffect(() => {
    const m = map.current,
      ls = layers.current;
    if (!m || !ls || !fields.length) return;
    ls.clearLayers();
    for (const f of fields) {
      const active = f.id === selected;
      const p = f.boundary.length
        ? L.polygon(
            f.boundary.map((x) => [x.lat, x.lng] as L.LatLngTuple),
            {
              color: active ? (basemap === "satellite" ? "#ffffff" : "#183f2b") : "#b9d795",
              weight: active ? 3 : 2,
              fillColor: active ? "#aec952" : "#a1b886",
              fillOpacity: active ? 0.18 : 0.08,
            },
          ).addTo(ls)
        : L.circleMarker([f.center.lat, f.center.lng], {
            radius: active ? 10 : 7,
            color: "#183f2b",
            fillColor: "#aec952",
            fillOpacity: 0.8,
            weight: 2,
          }).addTo(ls);
      const label = document.createElement("span");
      label.textContent = f.name;
      p.bindTooltip(label, {
        permanent: true,
        direction: "center",
        className: "field-label",
      });
      p.on("click", () => onSelect(f.id));
    }
    for (const observation of observations.filter(o=>o.location && o.fieldId===selected)) {
      const marker = L.circleMarker([observation.location!.lat, observation.location!.lng], {radius:7,color:"#ffffff",weight:3,fillColor:"#103F32",fillOpacity:1}).addTo(ls);
      const label = document.createElement("span");
      label.textContent = observation.note;
      marker.bindTooltip(label);
      marker.on("click",()=>onObservation?.(observation));
    }
    const f = fields.find((x) => x.id === selected);
    if (f?.boundary.length)
      m.fitBounds(
        L.latLngBounds(f.boundary.map((x) => [x.lat, x.lng] as L.LatLngTuple)),
        { padding: [45, 45], maxZoom: 14 },
      );
    else if (f) m.setView([f.center.lat, f.center.lng], 13);
  }, [fields, selected, onSelect, observations, onObservation, basemap]);
  return (
    <>
      <div
        ref={el}
        className="map"
        role="region"
        aria-label="Карта полей. Выбор поля также доступен в списке"
      />
      <div className="basemap-switch" role="group" aria-label="Подложка карты">
        {([['scheme', 'Схема'], ['satellite', 'Спутник']] as const).map(([value, label]) => (
          <button type="button" key={value} aria-pressed={basemap === value}
            onClick={() => { setTileError(""); setBasemap(value); }}>
            {label}
          </button>
        ))}
      </div>
      {tileError && (
        <span className="tile-error" role="status">
          {tileError}
        </span>
      )}
    </>
  );
}
