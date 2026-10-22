import type { AgentArtifact, AgentReply, Conversation, Observation } from '@agromax/contracts';

export function artifactIsStale(reply?: AgentReply, observation?: Observation): boolean {
  const artifact = reply?.artifact;
  return Boolean(artifact && observation && artifact.observationId === observation.id &&
    artifact.observationVersion !== undefined && artifact.observationVersion !== observation.version);
}

/** Retain historical evidence, but never reuse a previous version's question or mutation proposal. */
export function latestReply(conversation?: Conversation, observation?: Observation): AgentReply | undefined {
  const reply = conversation?.messages.slice().reverse().find(m => m.reply)?.reply;
  if (reply?.artifact?.observationId && reply.artifact.observationId !== observation?.id) return undefined;
  if (!reply || !artifactIsStale(reply, observation)) return reply;
  const artifact = reply.artifact!;
  return {
    ...reply,
    artifact: {
      ...artifact,
      question: undefined,
      proposedTask: undefined,
      actions: artifact.actions?.filter(action => action !== 'review_observation' && action !== 'start_revisit'),
    },
  };
}

export function evidenceReads(reply?: AgentReply) {
  const labels: Record<string, string> = { field_history: 'История поля прочитана', weather: 'Прогноз получен', source_search: 'Источники проверены', open_tasks: 'Задачи прочитаны' };
  return [...new Set(reply?.tools || [])].filter(tool => labels[tool]).map(tool => ({ tool, label: labels[tool] }));
}
export function chatPayload(fieldId: string, conversationId: string | undefined, message: string, provider: string, observationId?: string) {
  return { fieldId, conversationId, message: message.trim(), provider, observationId };
}

/** Only a proposal for this exact draft/version may prefill the human review form. */
export function reviewArtifact(artifact?: AgentArtifact, observation?: Observation): AgentArtifact | undefined {
  return observation?.status === 'draft' && artifact?.observationId === observation.id &&
    artifact.observationVersion === observation.version ? artifact : undefined;
}
