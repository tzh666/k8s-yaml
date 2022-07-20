#!/bin/bash
# 文件推送到git脚本
git add -A

git commit -m $1

git branch -M main

git push -u origin main