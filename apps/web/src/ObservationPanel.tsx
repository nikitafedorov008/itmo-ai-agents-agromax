import { useEffect, useState, type FormEvent } from "react";
import { Camera, MapPin, Check, ArrowUpRight } from "lucide-react";
import {
  ApiClient,
  type Observation,
  type AgentArtifact,
  type ObservationInput,
  type Point,
  type Photo,
  type Task,
} from "@agromax/contracts";
import { ORIGIN, date, errorText, operationId, clearOperation } from "./api";
export function PrivatePhoto({ id, api }: { id: string; api: ApiClient }) {
  const [url, setUrl] = useState(""),
    [failed, setFailed] = useState(false);
  useEffect(() => {
    let alive = true,
      object = "";
    const abort = new AbortController();
    fetch(ORIGIN + "/api/photos/" + encodeURIComponent(id), {
      headers: { Authorization: "Bearer " + api.token },
      signal: abort.signal,
    })
      .then((r) => {
        if (!r.ok) throw Error();
        return r.blob();
      })
      .then((b) => {
        object = URL.createObjectURL(b);
        if (alive) setUrl(object);
      })
      .catch(() => {
        if (alive) setFailed(true);
      });
    return () => {
      alive = false;
      abort.abort();
      if (object) URL.revokeObjectURL(object);
    };
  }, [id, api.token]);
  return url ? (
    <a href={url} target="_blank" rel="noreferrer">
      <img className="photo" src={url} alt="Фото наблюдения" />
    </a>
  ) : (
    <small>{failed ? "Фото недоступно" : "Загрузка фото…"}</small>
  );
}
export function ObservationForm({
  api,
  fieldId,
  parent,
  onSaved,
  onCancel,
}: {
  api: ApiClient;
  fieldId: string;
  parent?: string;
  onSaved: (o: Observation) => void;
  onCancel: () => void;
}) {
  const [note, setNote] = useState(""),
    [extent, setExtent] = useState(""),
    [location, setLocation] = useState<Point>(),
    [photos, setPhotos] = useState<Photo[]>([]),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  async function upload(file?: File) {
    if (!file) return;
    setBusy(true);
    setError("");
    try {
      const form = new FormData();
      form.append("file", file);
      const photo = await api.request<Photo>("/api/photos", {
        method: "POST",
        body: form,
      });
      setPhotos((p) => [...p, photo]);
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }
  function gps() {
    if (!navigator.geolocation) {
      setError(
        "Геолокация не поддерживается браузером. Наблюдение можно сохранить без координат.",
      );
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (p) => setLocation({ lat: p.coords.latitude, lng: p.coords.longitude }),
      () =>
        setError(
          "Не удалось получить координаты. Разрешите геолокацию или сохраните без неё.",
        ),
      { timeout: 10000 },
    );
  }
  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const input: ObservationInput = {
      fieldId,
      note,
      extent: extent || undefined,
      location,
      photoIds: photos.map((p) => p.id),
      parentObservationId: parent,
    };
    const key = "observation:" + JSON.stringify(input);
    try {
      const o = await api.request<Observation>("/api/observations", {
        method: "POST",
        body: JSON.stringify({ ...input, operationId: operationId(key) }),
      });
      clearOperation(key);
      onSaved(o);
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <form className="observation-form" onSubmit={save}>
      <div className="section-heading">
        <h3>{parent ? "Повторный осмотр" : "Новое наблюдение"}</h3>
        <button type="button" className="text-button" onClick={onCancel}>
          Отмена
        </button>
      </div>
      <p className="muted">
        Запишите факты с поля. Сохранение создаст черновик.
      </p>
      <label>
        Что вы заметили?
        <textarea
          required
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Например: на нижних листьях появились жёлтые пятна…"
          rows={4}
        />
      </label>
      <label>
        Масштаб / распространённость
        <input
          value={extent}
          onChange={(e) => setExtent(e.target.value)}
          placeholder="Например: 5% растений у лесополосы"
        />
      </label>
      <div className="button-row">
        <label className="upload">
          <Camera size={16} />
          Добавить фото
          <input
            type="file"
            accept="image/jpeg,image/png,image/webp"
            capture="environment"
            disabled={busy}
            onChange={(e) => upload(e.target.files?.[0])}
          />
        </label>
        <button type="button" className="outline" onClick={gps}>
          <MapPin size={16} />
          {location ? "GPS добавлен" : "GPS"}
        </button>
      </div>
      {location && (
        <small>
          {location.lat.toFixed(5)}, {location.lng.toFixed(5)}
        </small>
      )}
      {photos.map((p) => (
        <div className="upload-result" key={p.id}>
          <Check size={14} />
          {p.name}
          <button
            type="button"
            className="text-button"
            onClick={() => setPhotos((a) => a.filter((x) => x.id !== p.id))}
          >
            Убрать
          </button>
        </div>
      ))}
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      <button className="primary wide" disabled={busy}>
        {busy ? "Сохраняем…" : "Сохранить черновик"}
        <ArrowUpRight size={16} />
      </button>
    </form>
  );
}
export function ObservationDetail({
  observation: o,
  proposal,
  api,
  onChange,
  onRevisit,
}: {
  observation: Observation;
  proposal?: AgentArtifact;
  api: ApiClient;
  onChange: () => void;
  onRevisit: () => void;
}) {
  const [createTask, setCreateTask] = useState(true),
    [title, setTitle] = useState(
      proposal?.proposedTask?.title || "Повторно осмотреть участок",
    ),
    [due, setDue] = useState(() => {
      const date = proposal?.proposedTask
        ? new Date(proposal.proposedTask.dueAt)
        : new Date(Date.now() + 3 * 86400000);
      if (!proposal?.proposedTask) date.setHours(9, 0, 0, 0);
      return new Date(date.getTime() - date.getTimezoneOffset() * 60000)
        .toISOString()
        .slice(0, 16);
    }),
    [confirmed, setConfirmed] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  async function approve(e: FormEvent) {
    e.preventDefault();
    if (!confirmed) return;
    setBusy(true);
    setError("");
    const payload = {
      version: o.version,
      confirmed: true,
      task: createTask
        ? { title, dueAt: new Date(due).toISOString() }
        : undefined,
    };
    const key = "approve:" + o.id + JSON.stringify(payload);
    try {
      await api.request("/api/observations/" + o.id + "/approve", {
        method: "POST",
        body: JSON.stringify({ ...payload, operationId: operationId(key) }),
      });
      clearOperation(key);
      onChange();
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="detail">
      <div className="section-heading">
        <span
          className={"badge " + (o.status === "approved" ? "approved" : "")}
        >
          {o.status === "draft" ? "Черновик" : "Подтверждено"}
        </span>
        <small>{date(o.createdAt)}</small>
      </div>
      <h3>Наблюдение с поля</h3>
      {proposal && (
        <div className="callout">
          <strong>{proposal.title}</strong>
          <p className="prewrap">{proposal.body}</p>
          {proposal.proposedTask && (
            <small>
              {o.status === "draft"
                ? "Предложение задачи перенесено в форму ниже. Проверьте название и срок перед подтверждением."
                : "Запись уже подтверждена. Для новой задачи создайте повторный осмотр и подтвердите его отдельно."}
            </small>
          )}
        </div>
      )}
      <p className="prewrap">{o.note}</p>
      {o.extent && <p className="muted">Масштаб: {o.extent}</p>}
      {o.parentObservationId && (
        <small>Повторный осмотр · связан с предыдущим наблюдением</small>
      )}
      {o.location && (
        <p className="muted">
          <MapPin size={14} /> {o.location.lat.toFixed(5)},{" "}
          {o.location.lng.toFixed(5)}
        </p>
      )}
      <div className="photos">
        {o.photoIds.map((id) => (
          <PrivatePhoto key={id} id={id} api={api} />
        ))}
      </div>
      {o.status === "draft" ? (
        <form onSubmit={approve} className="approval">
          <h3>Решение агронома</h3>
          <p className="muted">
            Проверьте факты перед подтверждением. После подтверждения запись
            станет частью истории поля.
          </p>
          <label className="checkbox">
            <input
              type="checkbox"
              checked={createTask}
              onChange={(e) => setCreateTask(e.target.checked)}
            />
            Создать задачу на проверку
          </label>
          {createTask && (
            <>
              <label>
                Задача
                <input
                  required
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                />
              </label>
              <label>
                Срок
                <input
                  type="datetime-local"
                  required
                  value={due}
                  onChange={(e) => setDue(e.target.value)}
                />
              </label>
            </>
          )}
          <label className="checkbox">
            <input
              type="checkbox"
              required
              checked={confirmed}
              onChange={(e) => setConfirmed(e.target.checked)}
            />
            Я проверил наблюдение и подтверждаю действие
          </label>
          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
          <button className="primary wide" disabled={busy || !confirmed}>
            <Check size={17} />
            {busy
              ? "Подтверждаем…"
              : "Подтвердить" + (createTask ? " и создать задачу" : "")}
          </button>
        </form>
      ) : (
        <button className="outline wide" onClick={onRevisit}>
          Записать повторный осмотр
          <ArrowUpRight size={16} />
        </button>
      )}
    </div>
  );
}
export function TaskCard({
  task: t,
  api,
  onChange,
  onRevisit,
}: {
  task: Task;
  api: ApiClient;
  onChange: () => void;
  onRevisit: () => void;
}) {
  const [outcome, setOutcome] = useState(""),
    [confirmed, setConfirmed] = useState(false),
    [open, setOpen] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  async function complete(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    const payload = { version: t.version, confirmed: true, outcome };
    const key = "complete:" + t.id + JSON.stringify(payload);
    try {
      await api.request("/api/tasks/" + t.id + "/complete", {
        method: "POST",
        body: JSON.stringify({ ...payload, operationId: operationId(key) }),
      });
      clearOperation(key);
      onChange();
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <article className="task">
      <span className="eyebrow">
        {t.status === "done" ? "ВЫПОЛНЕНО" : "ДО " + date(t.dueAt)}
      </span>
      <h3>{t.title}</h3>
      {t.outcome && <p>{t.outcome}</p>}
      {t.status === "open" && !open && (
        <button className="text-button" onClick={() => setOpen(true)}>
          Зафиксировать результат →
        </button>
      )}
      {t.status === "open" && open && (
        <form onSubmit={complete}>
          <label>
            Результат проверки
            <textarea
              required
              value={outcome}
              onChange={(e) => setOutcome(e.target.value)}
              placeholder="Что изменилось после осмотра?"
            />
          </label>
          <label className="checkbox">
            <input
              type="checkbox"
              required
              checked={confirmed}
              onChange={(e) => setConfirmed(e.target.checked)}
            />
            Подтверждаю выполнение
          </label>
          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
          <button className="primary" disabled={busy || !confirmed}>
            {busy ? "Сохраняем…" : "Завершить задачу"}
          </button>
        </form>
      )}
      <button className="text-button" onClick={onRevisit}>
        Повторный осмотр
      </button>
    </article>
  );
}
