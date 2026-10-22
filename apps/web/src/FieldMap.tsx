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
  const [tileError, setTileError] = useState(false);
  const el = useRef<HTMLDivElement>(null);
  const map = useRef<L.Map | null>(null);
  const layers = useRef<L.LayerGroup | null>(null);
  useEffect(() => {
    if (!el.current) return;
    const m = L.map(el.current, { zoomControl: true }).setView([55.7, 37.6], 9);
    map.current = m;
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution:
        '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      maxZoom: 19,
    })
      .on("tileerror", () => setTileError(true))
      .addTo(m);
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
              color: active ? "#183f2b" : "#7a926d",
              weight: active ? 3 : 2,
              fillColor: active ? "#aec952" : "#a1b886",
              fillOpacity: active ? 0.48 : 0.25,
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
  }, [fields, selected, onSelect, observations, onObservation]);
  return (
    <>
      <div
        ref={el}
        className="map"
        role="region"
        aria-label="Карта полей. Выбор поля также доступен в списке"
      />
      {tileError && (
        <span className="tile-error" role="status">
          Подложка карты недоступна. Контуры и список полей доступны.
        </span>
      )}
    </>
  );
}
