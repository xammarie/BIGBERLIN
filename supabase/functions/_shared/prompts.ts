export type ActionType =
    | "correct"
    | "complete"
    | "fill_out"
    | "annotate"
    | "schrift_replace";

export type HandwritingMode = "library" | "adaptive";

const ACTION_INSTRUCTIONS: Record<ActionType, string> = {
    correct:
        "Identify any errors in the student's existing handwritten work. For each error, write a correction (strikethrough, replacement value, or short note) in the user's handwriting style. Do not change correct answers.",
    complete:
        "Identify unfinished work (blank fields, half-answered questions, missing steps) and complete them with the correct answers in the user's handwriting style. Leave already-completed work untouched.",
    fill_out:
        "Fill in every empty field, blank, and answer space on the worksheet with the correct answer in the user's handwriting style.",
    annotate:
        "Add helpful margin notes, underlines, brackets, arrows, and short hints next to relevant content in the user's handwriting style. Do not modify existing content.",
    schrift_replace:
        "Transcribe ALL existing handwritten text on each image VERBATIM, character-for-character. Then instruct the image editor to ERASE the existing handwriting and rewrite the EXACT same content in the user's handwriting style. Content must remain identical — only the visual style changes.",
};

const STYLE_INSTRUCTION: Record<HandwritingMode, string> = {
    library:
        "The image editor will receive the worksheet as the FIRST reference image and a handwriting sample as the SECOND reference image. In your prompt, instruct the editor to match the handwriting style shown in the second reference image when adding any new text or markings.",
    adaptive:
        "The image editor will receive ONLY the worksheet image. In your prompt, instruct the editor to match the handwriting style already present on the worksheet itself when adding any new text or markings.",
};

export function buildSystemPrompt(
    action: ActionType,
    mode: HandwritingMode,
    imageCount: number,
): string {
    return `You are the reasoning brain of a homework copilot. The user has uploaded ${imageCount} image${
        imageCount > 1 ? "s" : ""
    } and chosen the action: ${action.toUpperCase()}.

ACTION TASK
${ACTION_INSTRUCTIONS[action]}

HANDWRITING STYLE
${STYLE_INSTRUCTION[mode]}

OUTPUT CONTRACT (CRITICAL — READ CAREFULLY)
You output a JSON object with exactly this shape:
{
  "images": [
    { "index": 0, "standalone_prompt": "..." },
    { "index": 1, "standalone_prompt": "..." }
  ]
}

Each "standalone_prompt" will be sent to gpt-image-2 ALONE with only its own image (and the handwriting sample if mode=library). The image editor will NOT see other worksheet images, will NOT see chat memory, will NOT see this conversation.

THEREFORE EACH PROMPT MUST BE FULLY SELF-CONTAINED.
- DO NOT reference other images: never write "see image 1", "use the answer from page 2", "as on the previous worksheet", "as before".
- DO inline any cross-image data as concrete values: instead of "fill in the result from question 3", write "fill in the value 42 in the empty box for question 3".
- DO repeat any context the editor needs to do its job correctly on this single image.

CONTENT OF EACH PROMPT
Each "standalone_prompt" should contain:
1. A short summary of what to do on this specific image (1-2 sentences).
2. Concrete content to write/edit and exactly where (e.g. "in the empty box after the equation 5 + 7 =, write the number 12").
3. The visual style instruction from above (handwriting matching the sample / matching existing handwriting on the page).
4. A reminder to preserve the rest of the image unchanged (paper texture, printed text, layout, existing content not being edited).

REASONING APPROACH
You see all ${imageCount} images jointly so you can understand cross-image context. Use that context when generating per-image prompts, but bake the relevant context into each prompt as concrete inline data — never as a reference.

${
        action === "schrift_replace"
            ? `SCHRIFT_REPLACE SPECIFICS
For each image:
1. Transcribe ALL existing handwritten text on that image, verbatim, character-for-character. Include every word, number, symbol, line break.
2. Embed the full transcription INSIDE the standalone_prompt as quoted reference content.
3. Instruct the editor: "Erase all existing handwriting from this image and rewrite the following exact content in [the handwriting style described above]: <FULL_TRANSCRIPTION>". Preserve printed text, layout, paper background.`
            : ""
    }

OUTPUT ONLY THE JSON OBJECT. NO PREAMBLE, NO MARKDOWN FENCES, NO EXPLANATION.`;
}

export const GEMINI_RESPONSE_SCHEMA = {
    type: "object",
    properties: {
        images: {
            type: "array",
            items: {
                type: "object",
                properties: {
                    index: { type: "integer" },
                    standalone_prompt: { type: "string" },
                },
                required: ["index", "standalone_prompt"],
            },
        },
    },
    required: ["images"],
};
