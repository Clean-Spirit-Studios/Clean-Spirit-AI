

/// Splits a raw model response into a thinking trace and a final answer.
/// Looks for <think>...</think> block at the start of the response.
({String thinking, String answer}) splitThinking(String raw) {
  const openTag = '<think>';
  const closeTag = '</think>';

  final start = raw.indexOf(openTag);
  if (start == -1) return (thinking: '', answer: raw);

  final afterOpen = raw.substring(start + openTag.length);
  final end = afterOpen.indexOf(closeTag);
  if (end == -1) return (thinking: afterOpen.trimLeft(), answer: '');

  final thinking = afterOpen.substring(0, end).trim();
  final answer = afterOpen.substring(end + closeTag.length).trimLeft();
  return (thinking: thinking, answer: answer);
}