# -*- coding: utf-8 -*-
"""
Generator and benchmark script for:
1. Koori_no_Jouheki_single_actor.srt (based on 02 субтитры Koori no Jouheki 2nd Season.ass)
2. movie_length_with_actors.ass & .srt (1800 lines, ~1h 45min, with actors)
3. movie_length_no_actors.ass & .srt (1800 lines, ~1h 45min, without actors)
"""

import os
import re
import random
import time

def sec_to_srt_time(sec):
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = int(sec % 60)
    ms = int(round((sec - int(sec)) * 1000))
    if ms >= 1000:
        s += 1
        ms -= 1000
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

def sec_to_ass_time(sec):
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = int(sec % 60)
    cs = int(round((sec - int(sec)) * 100))
    if cs >= 100:
        s += 1
        cs -= 100
    return f"{h:d}:{m:02d}:{s:02d}.{cs:02d}"

def parse_ass_time(str_val):
    parts = str_val.strip().split(':')
    if len(parts) == 3:
        h = float(parts[0])
        m = float(parts[1])
        s = float(parts[2])
        return h * 3600 + m * 60 + s
    return 0.0

# -------------------------------------------------------------
# 1. Convert Koori no Jouheki ASS -> SRT with [Actor] Dialogue
# -------------------------------------------------------------
def convert_koori_to_srt(ass_path, srt_path):
    with open(ass_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()

    subs = []
    in_events = False
    format_cols = []
    start_idx, end_idx, name_idx, text_idx = None, None, None, None

    for line in lines:
        line_s = line.strip()
        if line_s.startswith('[Events]'):
            in_events = True
            continue
        elif line_s.startswith('[') and line_s.endswith(']'):
            in_events = False
            continue

        if in_events:
            if line_s.lower().startswith('format:'):
                header = line_s[7:].strip()
                format_cols = [c.strip().lower() for c in header.split(',')]
                for idx, col in enumerate(format_cols):
                    if col == 'start': start_idx = idx
                    elif col == 'end': end_idx = idx
                    elif col in ('name', 'actor'): name_idx = idx
                    elif col == 'text': text_idx = idx
            elif line_s.lower().startswith('dialogue:'):
                body = line_s[9:].strip()
                # Split body by commas up to format_cols - 1
                parts = []
                max_split = len(format_cols) - 1
                cur_pos = 0
                for _ in range(max_split):
                    comma_pos = body.find(',', cur_pos)
                    if comma_pos != -1:
                        parts.append(body[cur_pos:comma_pos].strip())
                        cur_pos = comma_pos + 1
                    else:
                        break
                parts.append(body[cur_pos:])

                t_start = parse_ass_time(parts[start_idx])
                t_end = parse_ass_time(parts[end_idx])
                actor = parts[name_idx].strip() if name_idx < len(parts) else "NoActor"
                text = parts[-1].strip() if parts else ""

                # Clean ASS text: strip {\...} and \N
                text = re.sub(r'\{[^}]+\}', '', text)
                text = text.replace(r'\N', ' ').replace(r'\n', ' ').replace(r'\h', ' ')
                text = re.sub(r'\s+', ' ', text).strip()

                if not actor or actor == "" or actor == "Надпись":
                    # Fallback natural actor for clean tests
                    actor = "Cherry Nice"

                # Single actor rule: if compound actor, take primary
                if ';' in actor: actor = actor.split(';')[0].strip()
                if '/' in actor: actor = actor.split('/')[0].strip()
                if '-' in actor: actor = actor.split('-')[0].strip()

                if text and t_end > t_start:
                    subs.append((t_start, t_end, actor, text))

    subs.sort(key=lambda s: s[0])

    with open(srt_path, 'w', encoding='utf-8') as f:
        for i, (t_start, t_end, actor, text) in enumerate(subs, 1):
            f.write(f"{i}\n")
            f.write(f"{sec_to_srt_time(t_start)} --> {sec_to_srt_time(t_end)}\n")
            f.write(f"[{actor}] {text}\n\n")

    return len(subs)

# -------------------------------------------------------------
# 2. Generate Movie-Length Subtitles (~1.75 hours, 1800 lines)
# -------------------------------------------------------------
PHRASES = [
    "Привет, ты сегодня рано.",
    "Мы должны успеть до заката, иначе будет поздно.",
    "Что ты думаешь по этому поводу?",
    "Я уверен, что всё будет в порядке, не волнуйся.",
    "Подожди меня здесь, я скоро вернусь.",
    "Где остальные члены команды? Они уже знают о случившемся?",
    "Это было совсем не так просто, как казалось сначала.",
    "Посмотри внимательно на карту, нам нужно свернуть на север.",
    "Не переживай раньше времени, запасной план сработает.",
    "Сколько времени у нас осталось до прибытия поезда?",
    "Держись крепче, сейчас будет крутой поворот!",
    "Я никогда раньше не видел ничего подобного в этих краях.",
    "Ты точно знаешь, что сейчас делаешь?",
    "Давай проверим ещё раз все показания приборов перед стартом.",
    "Всё готово к началу решающей фазы операции.",
    "Нам нельзя здесь больше задерживаться, нас могут заметить.",
    "Ты слышал этот странный звук из соседнего отсека?",
    "Кажется, кто-то приближается с противоположной стороны.",
    "Оставайся на связи, если что-то пойдёт не по плану.",
    "Мы обязательно справимся, главное не поддаваться панике.",
    "Отличная работа, именно этого результата я и ожидал.",
    "Ты уверен, что этот маршрут абсолютно безопасен?",
    "Нам нужно связаться со штабом как можно скорее.",
    "Я прикрою тебя, выдвигайся вперед без оглядки.",
    "Сделай глубокий вдох, всё самое сложное уже позади.",
    "У нас кончается горючее, нужно найти место для посадки.",
    "Эта информация меняет абсолютно всё наше понимание ситуации.",
    "Ты помнишь, о чём мы договаривались вчера вечером?",
    "Смотри под ноги, здесь могут быть скрытые ловушки.",
    "Сигнал перехвачен, нам нужно сменить частоту вещания.",
    "Я знал, что могу рассчитывать на твою помощь в этот момент.",
    "Ничего не трогай руками, пока сканирование не завершится.",
    "Мы уже почти у цели, осталось совсем немного потерпеть.",
    "Ты видел показания датчиков радиации на главном терминале?",
    "Давай разделимся, так у нас будет больше шансов найти выход.",
    "Это наш единственный шанс доказать свою правоту.",
    "Заблокируй все внешние шлюзы немедленно!",
    "Я проверю периметр, а ты оставайся у главного пульта управления.",
    "Не верь ни единому их слову, это очевидная провокация.",
    "Мы должны двигаться дальше, несмотря на погодные условия."
]

ACTORS = [
    ("Алексей", 0.30),
    ("Елена", 0.25),
    ("Дмитрий", 0.18),
    ("Ольга", 0.14),
    ("Михаил", 0.08),
    ("Диспетчер", 0.05)
]

def generate_movie_dataset(num_lines=1800):
    random.seed(42)  # Deterministic generation
    lines_data = []

    cur_time = 12.0  # Movie start after intro logos
    actor_names = [a[0] for a in ACTORS]
    actor_weights = [a[1] for a in ACTORS]

    for i in range(num_lines):
        dur = round(random.uniform(1.6, 3.8), 2)
        end_time = round(cur_time + dur, 2)
        phrase = PHRASES[i % len(PHRASES)]
        # Add slight variation occasionally
        if i % 7 == 0:
            phrase += " " + PHRASES[(i + 3) % len(PHRASES)]
        actor = random.choices(actor_names, weights=actor_weights)[0]

        lines_data.append((cur_time, end_time, actor, phrase))

        # Pause to next line
        pause = round(random.uniform(0.6, 2.8), 2)
        if i % 25 == 0:  # Occasional scene transition pause
            pause += round(random.uniform(3.0, 7.0), 2)
        cur_time = round(end_time + pause, 2)

    return lines_data

def write_movie_ass(lines_data, filepath, with_actors=True):
    header = """[Script Info]
Title: NutNotes Benchmark - Movie Subtitles
ScriptType: v4.00+
WrapStyle: 0
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,22,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,1,2,10,10,25,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(header)
        for t_start, t_end, actor, text in lines_data:
            act_field = actor if with_actors else ""
            f.write(f"Dialogue: 0,{sec_to_ass_time(t_start)},{sec_to_ass_time(t_end)},Default,{act_field},0,0,0,,{text}\n")

def write_movie_srt(lines_data, filepath, with_actors=True):
    with open(filepath, 'w', encoding='utf-8') as f:
        for idx, (t_start, t_end, actor, text) in enumerate(lines_data, 1):
            f.write(f"{idx}\n")
            f.write(f"{sec_to_srt_time(t_start)} --> {sec_to_srt_time(t_end)}\n")
            if with_actors:
                f.write(f"[{actor}] {text}\n\n")
            else:
                f.write(f"{text}\n\n")

if __name__ == "__main__":
    os.makedirs("examples", exist_ok=True)

    # 1. Koori no Jouheki single actor SRT
    koori_ass = "examples/02 субтитры Koori no Jouheki 2nd Season.ass"
    koori_srt = "examples/Koori_no_Jouheki_single_actor.srt"
    k_count = convert_koori_to_srt(koori_ass, koori_srt)
    print(f"1. Generated {koori_srt}: {k_count} subtitles")

    # 2. Movie length dataset
    movie_lines = generate_movie_dataset(1800)
    total_duration = movie_lines[-1][1]
    h = int(total_duration // 3600)
    m = int((total_duration % 3600) // 60)
    s = int(total_duration % 60)
    print(f"Generated movie dataset: 1800 lines, total runtime {h}h {m}m {s}s ({total_duration:.1f} sec)")

    # 2a. With actors
    ass_actors = "examples/movie_length_with_actors.ass"
    srt_actors = "examples/movie_length_with_actors.srt"
    write_movie_ass(movie_lines, ass_actors, with_actors=True)
    write_movie_srt(movie_lines, srt_actors, with_actors=True)
    print(f"2. Generated {ass_actors} & {srt_actors}")

    # 2b. Without actors
    ass_no_actors = "examples/movie_length_no_actors.ass"
    srt_no_actors = "examples/movie_length_no_actors.srt"
    write_movie_ass(movie_lines, ass_no_actors, with_actors=False)
    write_movie_srt(movie_lines, srt_no_actors, with_actors=False)
    print(f"3. Generated {ass_no_actors} & {srt_no_actors}")
