#!/usr/bin/env python
"""Rewrites the [input] section of project.godot.

Keeping the input map in code makes keyboard/mouse/gamepad bindings reviewable
instead of hand-editing serialized InputEvent objects.

    python tools/write_input_map.py
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "project.godot")


def key(code):
    return ('Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,'
            '"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,'
            '"keycode":0,"physical_keycode":%d,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)' % code)


def mouse(index):
    return ('Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,'
            '"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,'
            '"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":%d,"canceled":false,'
            '"pressed":false,"double_click":false,"script":null)' % index)


def joy_button(index):
    return ('Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,'
            '"button_index":%d,"pressure":0.0,"pressed":false,"script":null)' % index)


def joy_axis(axis, value):
    return ('Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,'
            '"axis":%d,"axis_value":%.1f,"script":null)' % (axis, value))


SPACE, SHIFT, ESC = 32, 4194325, 4194305
LEFT, UP, RIGHT, DOWN = 4194319, 4194320, 4194321, 4194322

ACTIONS = [
    # name, deadzone, events
    ("move_left", 0.2, [key(65), key(LEFT), joy_axis(0, -1.0)]),
    ("move_right", 0.2, [key(68), key(RIGHT), joy_axis(0, 1.0)]),
    ("move_forward", 0.2, [key(87), key(UP), joy_axis(1, -1.0)]),
    ("move_back", 0.2, [key(83), key(DOWN), joy_axis(1, 1.0)]),
    ("look_left", 0.15, [joy_axis(2, -1.0)]),
    ("look_right", 0.15, [joy_axis(2, 1.0)]),
    ("look_up", 0.15, [joy_axis(3, -1.0)]),
    ("look_down", 0.15, [joy_axis(3, 1.0)]),
    # Hold to charge, release to throw.
    ("throw_book", 0.4, [mouse(1), key(70), joy_axis(5, 1.0), joy_button(10)]),
    ("jump", 0.5, [key(SPACE), joy_button(0)]),
    ("dodge", 0.5, [key(SHIFT), mouse(2), joy_button(1), joy_button(9)]),
    ("camera_toggle", 0.5, [key(86), joy_button(3)]),
    ("pause", 0.5, [key(ESC), joy_button(6)]),
    ("scoreboard", 0.5, [key(4194306), joy_button(4)]),
    ("help", 0.5, [key(72)]),
]


def build():
    lines = ["[input]", ""]
    for name, deadzone, events in ACTIONS:
        lines.append("%s={" % name)
        lines.append('"deadzone": %s,' % deadzone)
        lines.append('"events": [' + ",\n".join(events))
        lines.append("]")
        lines.append("}")
    lines.append("")
    return "\n".join(lines) + "\n"


def main():
    with open(PATH, "r", encoding="utf-8") as handle:
        text = handle.read()
    new_text = re.sub(r"\[input\].*?(?=\n\[layer_names\])", build().rstrip("\n") + "\n", text, flags=re.S)
    with open(PATH, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(new_text)
    print("input map written:", ", ".join(a[0] for a in ACTIONS))


if __name__ == "__main__":
    main()
