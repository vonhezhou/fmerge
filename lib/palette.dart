import 'package:flutter/material.dart';

const bg = Color(0xff11151c);
const panel = Color(0xff171c25);
const elevated = Color(0xff1e2530);
const border = Color(0xff2a3341);
const muted = Color(0xff8f9bad);
const ink = Color(0xffd9e2ee);
const accent = Color(0xff98c5ff);
const green = Color(0xff8cdbac);
const red = Color(0xfff3a0a0);
const amber = Color(0xffe8c587);
const addedBg = Color(0xff19332c);
const removedBg = Color(0xff352429);
const addedInline = Color(0xff28583f);
const removedInline = Color(0xff67343e);
Color tokenColor(String scope) {
  final key = scope.split('.').first;
  return switch (key) {
    'keyword' || 'literal' => const Color(0xffc8a9ed),
    'string' || 'regexp' => const Color(0xffadd9ae),
    'number' => const Color(0xffe3bc87),
    'comment' => const Color(0xff798a9f),
    'title' || 'type' || 'built_in' => const Color(0xff8fc7ef),
    'meta' || 'attr' || 'attribute' => const Color(0xffe7bc8e),
    _ => ink,
  };
}
