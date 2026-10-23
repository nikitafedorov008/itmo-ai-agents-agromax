let data=Editor.getLoadedData().metrics.data.body;
if(typeof data==='string')data=JSON.parse(data);
if(data.schemaVersion!==1||data.scope!=='synthetic-demo-only')throw Error('Неверная схема метрик');
Editor.setRawData(data.events);
module.exports={render:Editor.wrapFn({args:[data],fn:function(options,m){
 const s=m.summary,e=m.events,ink='#e9efdf',muted='#a9b7a1',lime='#cbe579',red='#ec9b83';
 const esc=v=>String(v??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
 const fmt=v=>v===null||v===undefined?'н/д':String(Math.round(Number(v)*10)/10).replace('.',',');
 const pct=(a,b)=>b?fmt(a/b*100)+'%':'н/д';
 const sec=x=>x===null?'н/д':fmt(x/1000)+' с';
 const time=t=>t?new Date(Date.parse(t)+10800000).toISOString().slice(0,19).replace('T',' ')+' МСК':'н/д';
 const card=(label,value,note,color=lime)=>`<div style="flex:1;min-width:190px;padding:20px 0;border-top:1px solid #41533f"><div style="font-size:13px;color:${muted}">${esc(label)}</div><div style="font-size:38px;color:${color};font-weight:600;line-height:1.5">${esc(value)}</div><div style="font-size:12px;color:${muted};max-width:240px;line-height:1.5">${esc(note)}</div></div>`;
 const cards=x=>`<div style="display:flex;flex-wrap:wrap;gap:24px;margin:18px 0">${x.join('')}</div>`;
 const h=(n,t)=>`<h2 style="font-size:23px;font-weight:500;margin:32px 0 16px"><span style="font-size:13px;color:${lime};margin-right:18px">${n}</span>${esc(t)}</h2>`;
 const note=t=>`<p style="font-size:13px;color:${muted};line-height:1.65">${esc(t)}</p>`;
 const table=(heads,rows)=>`<div style="overflow:auto;border:1px solid #41533f;border-radius:10px;max-height:420px"><table style="width:100%;border-collapse:collapse;font-size:13px"><thead><tr>${heads.map(t=>`<th style="padding:12px;text-align:left;color:${ink};background:#293d2e">${esc(t)}</th>`).join('')}</tr></thead><tbody>${rows.length?rows.map(r=>`<tr>${r.map(v=>`<td style="padding:12px;border-top:1px solid #344b37;white-space:nowrap">${esc(v)}</td>`).join('')}</tr>`).join(''):`<tr><td colspan="${heads.length}" style="padding:18px;color:${muted}">Нет записей</td></tr>`}</tbody></table></div>`;
 const bars=items=>items.map(([label,value,color])=>`<div style="display:flex;align-items:center;gap:16px;margin:15px 0"><span style="width:170px;color:${muted};font-size:14px">${esc(label)}</span><div style="flex:1;background:#263b2b;border-radius:4px;height:22px"><div style="width:${Math.max(0,value)/Math.max(1,...items.map(x=>x[1]))*100}%;background:${color};height:22px;border-radius:4px"></div></div><strong style="width:50px;text-align:right">${esc(value)}</strong></div>`).join('');
 const groups={};for(const r of e){const k=r.provider;const g=groups[k]||(groups[k]={total:0,failed:0,ms:[]});g.total++;if(r.status==='failed')g.failed++;if(r.status==='completed'&&r.durationMs!==null)g.ms.push(r.durationMs);}
 const terminal=s.completed+s.failed,errors=e.filter(x=>x.status==='failed'),durationSample=e.filter(x=>x.status==='completed'&&x.durationMs!==null);
 const hourly=m.hourly.map(x=>[time(x.hour).slice(0,16),x.runs,x.completed,x.failed]);
 const toolCounts={};for(const r of e)for(const t of r.tools||[])toolCounts[t]=(toolCounts[t]||0)+1;
 const titleNames={field_history:'История поля',source_search:'Материалы FAO',open_tasks:'Открытые задачи',weather:'Прогноз погоды'};
 const content=`<div style="box-sizing:border-box;padding:32px;background:#14271d;color:${ink};font-family:Arial,sans-serif;height:${options.height}px;overflow-y:auto">
 <div style="display:flex;justify-content:space-between;gap:24px;align-items:start"><div><svg width="250" height="40" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 250 40" aria-label="AGROMAX" role="img"><rect width="40" height="40" rx="10" fill="#cbe579"/><path d="M9 25C8 11 19 6 32 9C33 23 24 32 11 29Z" fill="#18392c"/><path d="M11 29L28 12M19 21V13M19 21H27" fill="none" stroke="#cbe579" stroke-width="2"/><text x="52" y="29" font-family="Arial,sans-serif" font-size="28" font-weight="700" fill="#e9efdf">AGROMAX</text></svg><h1 style="font-size:32px;font-weight:500;margin-bottom:8px">Работа облачного агента</h1><div style="color:${muted};font-size:14px">Учебное демо-хозяйство · последние 30 суток · текущее состояние задач</div></div><div style="font-size:12px;color:${muted};text-align:right;line-height:1.8">Данные из API<br/><strong style="color:${lime}">${esc(time(m.snapshotAt))}</strong><br/>Последний запуск<br/>${esc(time(s.lastRunAt))}</div></div>
 ${cards([card('Запусков',s.runs,'completed + failed + running'),card('Успешность',pct(s.completed,terminal),'completed / завершённые; running отдельно'),card('Средний ответ',sec(s.meanMs),'цель ≤20 с; только completed с временем',s.meanMs>20000?red:lime),card('Технические ошибки',pct(s.failed,terminal),s.failed+' ошибок / '+terminal+' завершённых; цель ≤5%',s.failed?red:lime)])}
 ${note('Малая учебная выборка. Это реальные запросы к API на синтетических наблюдениях, не пилот в хозяйстве. Качество диагнозов и экономия времени человека не измерены.')}
 ${h('01','Результат процесса')}
 ${cards([card('Ответы с источниками',pct(s.withSources,s.completed),'ссылки / completed; не оценка качества'),card('Ответы с уточнением',pct(s.clarifications,s.completed),'clarification / completed; не ошибка'),card('Подтверждённые осмотры',s.approved,s.observations+' наблюдений сейчас'),card('Открытые задачи',s.openTasks,s.overdueTasks+' просрочено; требуется проверка',s.overdueTasks?red:lime)])}
 ${h('02','Стабильность и скорость')}${bars([['Завершены',s.completed,lime],['С ошибкой',s.failed,red],['Выполняются',s.running,'#91b8ab']])}
 ${note('p95: '+sec(s.p95Ms)+'; рассчитан по '+s.timedCompleted+' ответам. В малой выборке p95 не подтверждает SLA. '+s.legacyTimed+' старых интервалов восстановлены до timestamp ответа; новые — по finished_at базы.')}
 ${table(['Провайдер · последние 200','Запуски','Ошибки','Среднее, с'],Object.entries(groups).map(([name,g])=>[name,g.total,g.failed,g.ms.length?fmt(g.ms.reduce((a,b)=>a+b,0)/g.ms.length/1000):'н/д']))}
 ${h('03','Какие инструменты использованы')}${bars(Object.entries(toolCounts).map(([k,v])=>[titleNames[k]||k,v,lime]))}${note('Число ответов с каждым типом инструмента в последних 200 запусках. История и поиск источников выполняются сервером до цикла модели; это не все function calls, выбранные моделью.')}
 ${h('04','Внимание человека')}${note(s.failed?'Разобрать коды ошибок в журнале; проверить провайдера, формат ответа или хранилище. Данные наблюдения при ошибке модели не изменяются.':'Сбоев в выбранном демо-окне нет. Следить за running дольше пяти минут и просроченными задачами.')}
 ${table(['Время','Запуск','Провайдер','Код ошибки'],errors.map(r=>[time(r.startedAt),r.ref,r.provider,r.errorCode]))}
 ${h('05','Проверяемый журнал')}${table(['Начало · МСК','Запуск','Провайдер','Результат','Секунды','Источников','Уточнение'],e.map(r=>[time(r.startedAt),r.ref,r.provider,r.status,sec(r.durationMs),r.sourceCount,r.clarification?'Да':'Нет']))}
 ${h('06','Динамика по часам')}${table(['Начало часа · МСК','Запуски','Успех','Ошибка'],hourly)}
 ${note('Источник: сервер AGROMAX → Supabase agent_runs / observations / tasks → сервисная RPC → HTTPS API → DataLens. Автоматический запрос при обновлении экрана. Сводка — все события за 30 суток, журнал — последние 200. Фото, промпты, email, координаты и ключи не публикуются. Если API недоступен, чарт показывает ошибку, а не подставляет старые цифры.')}
 </div>`;
 return Editor.generateHtml(content);
}})};
