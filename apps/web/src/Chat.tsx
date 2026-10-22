import { useEffect, useRef, useState, type FormEvent } from "react";
import { ArrowUp, Sparkles, Plus, BookOpen } from "lucide-react";
import {
  ApiClient,
  type AgentArtifact,
  type ArtifactAction,
  type AgentReply,
  type Bootstrap,
  type Conversation,
  type Field,
  type Provider,
  type Observation,
} from "@agromax/contracts";
import { clearOperation, errorText, operationId } from "./api";
import { Workbench } from "./Workbench";
import { latestReply, chatPayload } from "./workbenchLogic";
import { isTerminalAgentFailure } from "./chatRetry";
export function Chat({
  api,
  field,
  data,
  onRefresh,
  onArtifact,
  onObservation,
  observation,
  onAction,
}: {
  api: ApiClient;
  field: Field;
  data: Bootstrap;
  onRefresh: () => void;
  onArtifact: (a: AgentArtifact) => void;
  onObservation: () => void;
  observation?: Observation;
  onAction: (action: ArtifactAction, artifact?: AgentArtifact) => void;
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
    [error, setError] = useState(""),
    [terminalKey, setTerminalKey] = useState<string | null>(null);
  const drawer = useRef<HTMLDialogElement>(null);
  const [localConversation, setLocalConversation] = useState<Conversation>();
  const messagesRef = useRef<HTMLDivElement>(null);
  const abort = useRef<AbortController | null>(null);
  const active = useRef(true);
  useEffect(() => {
    active.current = true;
    return () => {
      active.current = false;
      abort.current?.abort();
    };
  }, []);
  const conversation = localConversation?.id === conversationId ? localConversation : conversations.find((c) => c.id === conversationId);
  const reply = latestReply(conversation, observation);
  useEffect(() => {
    if (reply?.provider) setProvider(reply.provider);
  }, [conversationId, reply?.provider]);
  useEffect(() => {
    if (!conversation?.messages.length && !busy) return;
    const list = messagesRef.current;
    list?.scrollTo({ top: list.scrollHeight, behavior: "smooth" });
  }, [conversation?.messages.length, busy]);
  const payload = {
    fieldId: field.id,
    conversationId,
    message: message.trim(),
    provider,
    observationId: observation?.id,
  };
  const currentKey = "chat:" + JSON.stringify(payload);
  const needsNewAttempt = terminalKey === currentKey;
  async function send(e: FormEvent) {
    e.preventDefault();
    await sendMessage(false);
  }
  async function sendMessage(newAttempt: boolean, answer?: string) {
    const outgoing = answer ?? message;
    const requestPayload = chatPayload(field.id, conversationId, outgoing, provider, observation?.id);
    const requestKey = "chat:" + JSON.stringify(requestPayload);
    if (terminalKey === requestKey && !newAttempt) { drawer.current?.showModal(); return; }
    if (newAttempt) clearOperation(requestKey);
    if (!outgoing.trim() || busy) return;
    setBusy(true);
    setError("");
    setTerminalKey(null);
    const key = requestKey;
    const controller = new AbortController();
    abort.current = controller;
    try {
      const r = await api.request<{
        conversation: Conversation;
        reply: AgentReply;
      }>("/api/agent/chat", {
        method: "POST",
        body: JSON.stringify({ ...requestPayload, operationId: operationId(key) }),
        signal: controller.signal,
      });
      if (!active.current) return;
      clearOperation(key);
      setConversationId(r.conversation.id);
      setLocalConversation(r.conversation);
      setMessage("");
      if (r.reply.artifact) onArtifact(r.reply.artifact);
      onRefresh();
    } catch (e) {
      if (
        active.current &&
        !(e instanceof DOMException && e.name === "AbortError")
      ) {
        setError(errorText(e));
        if (isTerminalAgentFailure(e)) setTerminalKey(key);
      }
    } finally {
      if (active.current) setBusy(false);
    }
  }
  return (
    <section className="workbench-panel">
      <div className="workbench-heading"><div><span className="eyebrow">ОСМОТР ПОЛЯ</span><h2>{field.name} <span>· {field.crop}</span></h2></div><label>Модель<select aria-label="Модель анализа" disabled={busy} value={provider} onChange={e=>setProvider(e.target.value as Provider)}>{data.providers.map(p=><option key={p.id} value={p.id}>{p.id === "deepseek" ? "DeepSeek" : "MiMo"}{p.configured ? "" : " · не подключена"}</option>)}</select></label></div>
      <Workbench api={api} observation={observation} reply={reply} busy={busy} onSend={answer=>{setMessage(answer);void sendMessage(false, answer)}} onObserve={onObservation} onDiscuss={()=>drawer.current?.showModal()} onAction={action=>action === "reply"?drawer.current?.showModal():onAction(action, action === "review_observation" ? reply?.artifact : undefined)}/>
      {error && <div className="error workbench-error" role="alert">{error}<button className="text-button" onClick={()=>drawer.current?.showModal()}>Открыть запрос и повторить</button></div>}
      <dialog ref={drawer} className="discussion-dialog" aria-label="Обсуждение поля"><div className="chat-panel">
      <button className="outline close-discussion" onClick={()=>drawer.current?.close()}>Закрыть обсуждение</button>
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
          disabled={busy}
          onClick={() => {
            setConversationId(undefined);
            setLocalConversation(undefined);
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
          disabled={busy}
          value={provider}
          onChange={(e) => setProvider(e.target.value as Provider)}
        >
          <option value="deepseek">DeepSeek</option>
          <option value="mimo">MiMo</option>
        </select>
      </div>
      {observation && (
        <p className="selected-observation">
          Контекст: наблюдение от{" "}
          {new Date(observation.createdAt).toLocaleDateString("ru-RU")}
        </p>
      )}
      {conversations.length > 0 && (
        <select
          className="history-select"
          aria-label="История разговоров"
          disabled={busy}
          value={conversationId || ""}
          onChange={(e) => {setConversationId(e.target.value || undefined); setLocalConversation(undefined)}}
        >
          <option value="">Новый разговор</option>
          {conversations.map((c) => (
            <option value={c.id} key={c.id}>
              {c.messages[0]?.text.slice(0, 55) || "Разговор"}
            </option>
          ))}
        </select>
      )}
      <div ref={messagesRef} className="messages" aria-live="polite">
        {!conversation?.messages.length && (
          <div className="chat-empty">
            <div className="spark-icon">
              <Sparkles size={27} />
            </div>
            <span className="eyebrow">КОНТЕКСТ ПОЛЯ ПОДКЛЮЧЁН</span>
            <h3>
              Что происходит на вашем поле?
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
      </div>
      <div className="composer">
        <button className="text-button" onClick={onObservation}>
          <Plus size={15} />
          Наблюдение с фото
        </button>
        {error && (
          <div className="error" role="alert">
            <p>{error}</p>
            {needsNewAttempt ? (
              <>
                <p>
                  Попытка завершилась с ошибкой. Провайдер мог уже списать
                  оплату, особенно при тайм-ауте. Новая попытка отправит
                  отдельный запрос и может тарифицироваться повторно.
                </p>
                <button
                  type="button"
                  className="outline"
                  disabled={busy}
                  onClick={() => void sendMessage(true)}
                >
                  Отправить как новую попытку
                </button>
              </>
            ) : (
              <p>
                Повторная отправка проверит тот же запрос без создания новой
                операции. При сетевой ошибке или выполняющемся запросе дождитесь
                результата.
              </p>
            )}
          </div>
        )}
        <form onSubmit={send}>
          <textarea
            aria-label="Сообщение помощнику"
            disabled={busy}
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
            disabled={busy || !message.trim() || needsNewAttempt}
          >
            <ArrowUp size={20} />
          </button>
        </form>
        <small>Проверяйте выводы ИИ. Действия подтверждает агроном.</small>
      </div>
    </div></dialog></section>
  );
}
