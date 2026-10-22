import { useState } from 'react';
import { BookOpen, Check, CloudSun, FileText, Leaf, MessageSquare, Sparkles, ArrowRight } from 'lucide-react';
import type { AgentReply, ApiClient, ArtifactAction, Observation } from '@agromax/contracts';
import { PrivatePhoto } from './ObservationPanel';
import { artifactIsStale, evidenceReads } from './workbenchLogic';
export function Workbench({ api, observation, reply, busy, onSend, onObserve, onDiscuss, onAction }: {
  api: ApiClient; observation?: Observation; reply?: AgentReply; busy: boolean;
  onSend: (message: string) => void; onObserve: () => void; onDiscuss: () => void;
  onAction: (action: ArtifactAction) => void;
}) {
  const [answer, setAnswer] = useState('');
  const [sourcesOpen, setSourcesOpen] = useState(false);
  const artifact = reply?.artifact;
  const stale = artifactIsStale(reply, observation);
  const question = stale ? undefined : artifact?.question;
  const stage = artifact?.stage || (reply ? 'context' : 'signs');
  const reads = evidenceReads(reply);
  const actions: Record<ArtifactAction, string> = {reply:'Ответить помощнику',review_observation:'Проверить и подтвердить',start_revisit:'Повторный осмотр',open_history:'История поля',open_weather:'Погода',view_sources:'Обоснование'};
  return <div className="observation-workbench">
    <ol className="stages" aria-label="Этапы осмотра">{(['signs','context','decision'] as const).map((s,i)=><li key={s} aria-current={stage===s?'step':undefined}><span>{stage===s?<Leaf size={17}/>:i+1}</span>{['Признаки','Контекст','Решение'][i]}</li>)}</ol>
    <div className="observation-hero">
      <div className="botanical-photo">{observation?.photoIds[0]?<PrivatePhoto id={observation.photoIds[0]} api={api}/>:<><img src="/wheat-leaf.png" alt="Ботаническая иллюстрация листа пшеницы" onError={e=>{e.currentTarget.style.display='none'}}/><span className="illustration-label">Иллюстрация культуры</span><Leaf className="illustration-fallback" size={90}/></>}</div>
      <section className="observed-note"><div className="section-heading"><span className="eyebrow">{observation?'ВЫ ОТМЕТИЛИ':'НАЧНИТЕ С НАБЛЮДЕНИЯ'}</span><FileText size={20}/></div><h3>{observation?'Признаки с поля':'Что изменилось на растениях?'}</h3><p className="prewrap">{observation?.note || 'Сфотографируйте участок и опишите то, что видите. Сопоставим вашу запись с историей поля и погодой.'}</p>{observation?.extent&&<span className="context-chip">{observation.extent}</span>}<button className="outline" onClick={onObserve}>{observation?'Добавить наблюдение':'Фото и заметка'} <ArrowRight size={16}/></button></section>
    </div>
    <section className="ai-evidence" aria-live="polite"><div className="section-heading"><Sparkles size={25}/><h2>{busy?'Сопоставляем контекст':artifact?.title || 'Контекст для решения'}</h2></div><p>{busy?'Ожидаем ответ помощника. Результаты появятся после завершения запроса.':artifact?.body || reply?.text || 'История поля и прогноз доступны для анализа. Начните с фактов или задайте вопрос помощнику.'}</p>
      <div className="evidence-grid">{[{tool:'field_history',label:'История поля',icon:FileText,action:'open_history' as const},{tool:'weather',label:'Погода',icon:CloudSun,action:'open_weather' as const}].map(({tool,label,icon:Icon,action})=><button onClick={()=>onAction(action)} key={tool}><Icon size={25}/><span><strong>{label}</strong><small>{!busy&&reads.find(r=>r.tool===tool)?<><Check size={13}/> Прочитано в ответе</>:'Открыть данные'}</small></span></button>)}</div>
      {!busy && reads.length>0 && <p className="read-summary">{reads.map(r=>r.label).join(' · ')}</p>}{busy&&<div className="agent-running" role="status"><span className="spinner"/> Запрос выполняется</div>}
    </section>
    {stale&&<p className="stale-answer" role="status">Этот ответ относится к предыдущей версии наблюдения. Выводы сохранены для справки; проверьте текущую запись.</p>}
    {question&&!busy&&<section className="clarification"><span className="eyebrow">ВОПРОС ПОМОЩНИКА</span><h2>{question.prompt}</h2><div className="answer-options">{question.options.map(option=><button className="outline" key={option} onClick={()=>onSend(option)} disabled={busy}>{option}</button>)}</div>{question.allowCustom&&<form onSubmit={e=>{e.preventDefault();if(answer.trim())onSend(answer)}}><label>Ваш ответ<textarea value={answer} onChange={e=>setAnswer(e.target.value)} required rows={2}/></label><button className="primary" disabled={busy||!answer.trim()}>Добавить ответ и продолжить <ArrowRight size={17}/></button></form>}</section>}
    {reply&&<details className="evidence-sources" open={sourcesOpen} onToggle={e=>setSourcesOpen(e.currentTarget.open)}><summary><BookOpen size={19}/> Обоснование · {reply.sources.length} источников</summary>{reply.sources.length?reply.sources.map(s=><article key={s.id}><a href={/^https?:\/\//.test(s.url)?s.url:undefined} target="_blank" rel="noreferrer">{s.title}</a><p>{s.excerpt}</p><small>Версия {s.version}</small></article>):<p>В этом ответе нет цитируемых источников.</p>}</details>}
    <div className="workbench-actions">{!reply&&!busy&&<button className="primary wide" onClick={()=>observation?onSend('Помоги разобраться в текущем наблюдении. Сопоставь признаки с историей поля и уточни недостающие факты.'):onDiscuss()}>Сопоставить контекст <ArrowRight size={17}/></button>}{artifact?.actions?.map(action=><button className={action==='review_observation'?'primary':'outline'} key={action} disabled={busy||(['review_observation','start_revisit'].includes(action)&&!observation)} onClick={()=>action==='view_sources'?setSourcesOpen(true):onAction(action)}>{actions[action]}</button>)}{observation&&!artifact?.actions?.includes(observation.status==='approved'?'start_revisit':'review_observation')&&<button className="primary" onClick={()=>onAction(observation.status==='approved'?'start_revisit':'review_observation')}>{observation.status==='approved'?'Записать повторный осмотр':stale?'Открыть текущую запись':'Проверить наблюдение'}</button>}<button className="outline wide discuss-button" onClick={onDiscuss}><MessageSquare size={19}/> Обсудить свободно</button></div>
  </div>;
}
