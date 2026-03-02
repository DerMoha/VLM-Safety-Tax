import re


def remove_deepseek_r1_thinking(input: str) -> str:
    if "<think>" not in input:
        return input

    if "</think>\n\n" in input:
        # The think block is usually followed by two newlines, so we should remove that
        return re.sub("<think>.*</think>\n\n", "", input, flags=re.DOTALL)
    elif "</think>" in input:
        return re.sub("<think>.*</think>", "", input, flags=re.DOTALL)
    else:
        # Unclosed think block
        return ""

def remove_r1_thinking_and_answer_tags(input: str) -> str:
    """Strip <think>...</think> and extract content from <answer>...</answer> if present."""
    import re
    text = re.sub(r"<think>.*?</think>", "", input, flags=re.DOTALL | re.IGNORECASE).strip()
    answer_match = re.search(r"<answer>(.*?)</answer>", text, flags=re.DOTALL | re.IGNORECASE)
    if answer_match:
        text = answer_match.group(1).strip()
    # Unclosed think block: no usable answer
    if text.startswith("<think>"):
        text = ""
    # Strip "Final Answer:" prefix (Vision-R1 format)
    if text.startswith("Final Answer:"):
        text = text[len("Final Answer:"):].strip()
    return text