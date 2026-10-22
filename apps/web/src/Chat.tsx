import { useEffect, useRef, useState, type FormEvent } from "react";
import { ArrowUp, Sparkles, Plus, BookOpen } from "lucide-react";
import {
  ApiClient,
  type AgentArtifact,
  type AgentReply,
  type Bootstrap,
  type Conversation,
  type Field,
  type Provider,
} from "@agromax/contracts";
import { clearOperation, errorText, operationId } from "./api";
export function Chat({
  api,
  field,
  data,
  onRefresh,
  onArtifact,
  onObservation,
}: {
  api: ApiClient;
  field: Field;
  data: Bootstrap;
  onRefresh: () => void;
  onArtifact: (a: AgentArtifact) => void;
  onObservation: () => void;
}) {
  const conversations = data.conversations.filter(
    (c) => c.fieldId === field.id,
  );
  const [conversationId, setConversationId] = useState<string | undefined>(
      conversations[0]?.id,
    ),
    [provider, setProvider] = useState<Provider>("deepseek"),
    [message, setMessage] = useState(""),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const bottom = useRef<HTMLDivElement>(null);
  const abort = useRef<AbortController | null>(null);
  const active = useRef(true);
  useEffect(() => {
    active.current = true;
    return () => {
      active.current = false;
      abort.current?.abort();
    };
  }, []);
  const conversation = conversations.find((c) => c.id === conversationId);
  useEffect(
    () =>
      bottom.current?.scrollIntoView({ block: "nearest", behavior: "smooth" }),
    [conversation?.messages.length, busy],
  );
  async function send(e: FormEvent) {
    e.preventDefault();
    if (!message.trim() || busy) return;
    setBusy(true);
    setError("");
    const payload = {
      fieldId: field.id,
      conversationId,
      message: message.trim(),
      provider,
    };
    const key = "chat:" + JSON.stringify(payload);
    const controller = new AbortController();
    abort.current = controller;
    try {
      const r = await api.request<{
        conversation: Conversation;
        reply: AgentReply;
      }>("/api/agent/chat", {
        method: "POST",
        body: JSON.stringify({ ...payload, operationId: operationId(key) }),
        signal: controller.signal,
      });
      if (!active.current) return;
      clearOperation(key);
      setConversationId(r.conversation.id);
      setMessage("");
      if (r.reply.artifact) onArtifact(r.reply.artifact);
      onRefresh();
    } catch (e) {
      if (
        active.current &&
        !(e instanceof DOMException && e.name === "AbortError")
      )
        setError(errorText(e));
    } finally {
      if (active.current) setBusy(false);
    }
  }
  return (
    <section className="chat-panel">
      <header className="panel-header">
        <div>
          <span className="eyebrow">АГРОНОМИЧЕСКИЙ ПОМОЩНИК</span>
          <h2>
            <Sparkles size={18} />
            Разобраться в ситуации
          </h2>
        </div>
        <button
          className="icon-button"
          aria-label="Новый разговор"
          onClick={() => {
            setConversationId(undefined);
            setError("");
          }}
        >
          <Plus size={18} />
        </button>
      </header>
      <div className="chat-context">
        <span className="context-dot" />
        {field.name}
        <span>·</span>
        {field.crop}
        <select
          aria-label="Модель помощника"
          value={provider}
          onChange={(e) => setProvider(e.target.value as Provider)}
        >
          <option value="deepseek">DeepSeek</option>
          <option value="mimo">MiMo</option>
        </select>
      </div>
      {conversations.length > 0 && (
        <select
          className="history-select"
          aria-label="История разговоров"
          value={conversationId || ""}
          onChange={(e) => setConversationId(e.target.value || undefined)}
        >
          <option value="">Новый разговор</option>
          {conversations.map((c) => (
            <option value={c.id} key={c.id}>
              {c.messages[0]?.text.slice(0, 55) || "Разговор"}
            </option>
          ))}
        </select>
      )}
      <div className="messages" aria-live="polite">
        {!conversation?.messages.length && (
          <div className="chat-empty">
            <div className="spark-icon">
              <Sparkles size={27} />
            </div>
            <span className="eyebrow">КОНТЕКСТ ПОЛЯ ПОДКЛЮЧЁН</span>
            <h3>
              Что происходит
              <br />
              на вашем поле?
            </h3>
            <p>
              Опишите симптом или задайте вопрос. Помощник учтёт историю
              наблюдений, задачи и погоду.
            </p>
            <div className="suggestions">
              {[
                "На что обратить внимание при осмотре?",
                "Какие задачи по этому полю?",
                "Как погода повлияет на работы?",
              ].map((t) => (
                <button key={t} onClick={() => setMessage(t)}>
                  {t}
                  <span>↗</span>
                </button>
              ))}
            </div>
          </div>
        )}
        {conversation?.messages.map((m) => (
          <article className={"message " + m.role} key={m.id}>
            <span className="message-author">
              {m.role === "user"
                ? "ВЫ"
                : `AGROMAX · ${m.reply?.model || "Помощник"}`}
            </span>
            <p className="prewrap">{m.text}</p>
            {m.reply?.sources?.length ? (
              <div className="sources">
                <BookOpen size={14} />
                {m.reply.sources.map((s) => (
                  <a
                    key={s.id}
                    href={s.url}
                    target="_blank"
                    rel="noreferrer"
                    title={s.excerpt}
                  >
                    {s.title}
                  </a>
                ))}
              </div>
            ) : null}
            {m.reply?.artifact && (
              <button
                className="artifact-link"
                onClick={() => onArtifact(m.reply!.artifact!)}
              >
                <span>Открыть материал</span>
                {m.reply.artifact.title} ↗
              </button>
            )}
            {m.reply?.requiresConfirmation && (
              <small>
                Предложение помощника требует вашей проверки и подтверждения.
              </small>
            )}
          </article>
        ))}
        {busy && (
          <p className="thinking" role="status">
            Помощник изучает контекст поля<span>…</span>
          </p>
        )}
        <div ref={bottom} />
      </div>
      <div className="composer">
        <button className="text-button" onClick={onObservation}>
          <Plus size={15} />
          Наблюдение с фото
        </button>
        {error && (
          <p className="error" role="alert">
            {error} Повторная отправка сохранит тот же идентификатор операции.
          </p>
        )}
        <form onSubmit={send}>
          <textarea
            aria-label="Сообщение помощнику"
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            placeholder="Опишите, что заметили на поле…"
            rows={2}
            required
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                e.currentTarget.form?.requestSubmit();
              }
            }}
          />
          <button
            aria-label="Отправить сообщение"
            className="send"
            disabled={busy || !message.trim()}
          >
            <ArrowUp size={20} />
          </button>
        </form>
        <small>Проверяйте выводы ИИ. Действия подтверждает агроном.</small>
      </div>
    </section>
  );
}
