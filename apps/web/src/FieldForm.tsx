import { useEffect, useRef, useState, type FormEvent } from "react";
import { ApiClient, type Field, type Point } from "@agromax/contracts";
import { clearOperation, errorText, operationId } from "./api";
export function FieldForm({
  api,
  onClose,
  onSaved,
}: {
  api: ApiClient;
  onClose: () => void;
  onSaved: (field: Field) => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  useEffect(() => {
    ref.current?.showModal();
  }, []);
  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError("");
    const form = new FormData(e.currentTarget);
    const name = String(form.get("name")).trim(),
      crop = String(form.get("crop")).trim(),
      areaHa = Number(form.get("area"));
    const raw = String(form.get("boundary")).trim();
    const lines = raw ? raw.split(/\n/) : [];
    const boundary: Point[] = lines.map((line) => {
      const [lat, lng] = line
        .trim()
        .split(/[,;\s]+/)
        .map(Number);
      return { lat, lng };
    });
    if (
      (boundary.length > 0 && boundary.length < 3) ||
      boundary.some(
        (p) =>
          !Number.isFinite(p.lat) ||
          !Number.isFinite(p.lng) ||
          Math.abs(p.lat) > 90 ||
          Math.abs(p.lng) > 180,
      )
    ) {
      setError(
        "Укажите не менее трёх точек: широта и долгота через запятую, каждая точка с новой строки.",
      );
      return;
    }
    const center = {
      lat: Number(form.get("lat")),
      lng: Number(form.get("lng")),
    };
    const payload = { confirmed: true, name, crop, areaHa, center, boundary };
    const key = "field:" + JSON.stringify(payload);
    setBusy(true);
    try {
      const field = await api.request<Field>("/api/fields", {
        method: "POST",
        body: JSON.stringify({ ...payload, operationId: operationId(key) }),
      });
      clearOperation(key);
      onSaved(field);
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <dialog ref={ref} className="field-dialog" onCancel={onClose}>
      <div className="section-heading">
        <h2>Добавить поле</h2>
        <button type="button" className="text-button" onClick={onClose}>
          Закрыть
        </button>
      </div>
      <p className="muted">
        Введите реальные сведения и положение поля. Контур можно добавить
        отдельно; без него поле отобразится точкой.
      </p>
      <form onSubmit={submit}>
        <label>
          Название
          <input
            autoFocus
            name="name"
            required
            placeholder="Например: Северное"
          />
        </label>
        <label>
          Культура
          <input name="crop" required placeholder="Например: озимая пшеница" />
        </label>
        <label>
          Площадь, га
          <input name="area" type="number" min="0.01" step="0.01" required />
        </label>
        <div className="coordinate-row">
          <label>
            Широта центра
            <input
              name="lat"
              type="number"
              min="-90"
              max="90"
              step="any"
              required
              placeholder="55.75"
            />
          </label>
          <label>
            Долгота центра
            <input
              name="lng"
              type="number"
              min="-180"
              max="180"
              step="any"
              required
              placeholder="37.61"
            />
          </label>
        </div>
        <label>
          Контур (необязательно): широта, долгота
          <textarea
            name="boundary"
            rows={5}
            placeholder={"55.751, 37.610\n55.755, 37.620\n55.749, 37.625"}
          />
        </label>
        <p className="fine">
          Без контура сохраняется только точка. Если вводите границу, каждая
          вершина — с новой строки. Минимум три точки, в порядке обхода границы.
          Пример в подсказке не сохраняется автоматически.
        </p>
        <label className="checkbox">
          <input type="checkbox" required />
          Подтверждаю сведения и положение поля
        </label>
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        <button className="primary wide" disabled={busy}>
          {busy ? "Сохраняем…" : "Создать поле"}
        </button>
      </form>
    </dialog>
  );
}
