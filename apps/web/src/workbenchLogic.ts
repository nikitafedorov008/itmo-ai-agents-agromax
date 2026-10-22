import type { AgentReply, Conversation, Observation } from '@agromax/contracts';
/** Do not apply another observation's decision or clarifying question to this context. */
export function latestReply(conversation?: Conversation, observation?: Observation): AgentReply | undefined {
  const reply = conversation?.messages.slice().reverse().find(m => m.reply)?.reply;
  return reply?.artifact?.observationId && reply.artifact.observationId !== observation?.id ? undefined : reply;
}
export function evidenceReads(reply?: AgentReply) {
  const labels: Record<string, string> = { field_history: 'История поля прочитана', weather: 'Прогноз получен', source_search: 'Источники проверены', open_tasks: 'Задачи прочитаны' };
  return [...new Set(reply?.tools || [])].filter(tool => labels[tool]).map(tool => ({ tool, label: labels[tool] }));
}
export function chatPayload(fieldId: string, conversationId: string | undefined, message: string, provider: string, observationId?: string) {
  return { fieldId, conversationId, message: message.trim(), provider, observationId };
}
