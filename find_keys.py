with open(r'E:\AI_agent_space\ReaperPortableBase — копия\Scripts\NutNotes\reaper_imgui_doc.html', 'r', encoding='utf-8') as f:
    text = f.read()

import re
matches = re.finditer(r'<details id="([^"]+)"><summary>[^<]*</summary>(.*?)</details>', text, re.DOTALL)
for m in matches:
    name, body = m.group(1), m.group(2)
    if any(k in body.lower() for k in ['reaper shortcut', 'unhandled key', 'passthrough', 'forward', 'accelerator']):
        print('Matched:', name)
        # print description
        clean = re.sub(r'<[^>]+>', ' ', body)
        print(' ', ' '.join(clean.split())[:300])
