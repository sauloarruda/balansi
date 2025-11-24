# Pitch — Balansi v1

## Problem

People trying to improve their health, body composition, and training consistency often fail because they lack a simple, fast, and reliable way to record what they eat, how they train, and how these choices affect their daily and weekly progress.

Existing tools are too complex, require excessive manual input, focus too heavily on calorie tracking, or produce poor reports. For someone who just wants a clear view of *“what I did today and whether it was good or bad”*, the current workflow is far too heavy.

## Bet

Build an extremely fast, lightweight, feedback-oriented nutrition and training journal. The user logs meals and workouts in a simple way and automatically receives:

- macro and protein calculations
- calorie estimates
- daily calorie balance
- a daily score (1 to 5)
- analysis and guidance

v1 focuses on **log**, **calculate**, and **evaluate**. No complex graphs, heavy onboarding, community features, or gamification.
The goal is to create an “evaluative daily journal” that the user can complete in seconds and trust. LLMs interpret user input, calculate macros and calories, assign a score, and generate recommendations.

## Appetite

6 weeks (10 hours per week) to deliver a functional version able to:

- Log meals using free-text descriptions
- Automatically estimate calories and macros
- Log workouts using free-text descriptions
- Calculate daily totals + score based on predefined rules
- Save history in a database

## Proposed Solution

An ultra-minimalist interface divided into four parts:

1. **Basic onboarding and setup**
2. **Logging meals and workouts**
   - Free-text input
   - LLM interprets text, extracts foods/exercises, and estimates macros
3. **Automatic Calculation**
   - Internal engine sums macros, total protein, calories consumed, and calories burned
   - Applies scoring rules (deficit/maintenance, protein intake, exercise, alcohol, etc.) and generates a daily score (1 to 5)
4. **Daily Summary**
   Displays:
   - complete daily table of foods and exercises
   - total macros
   - calorie balance
   - score and recommendations

## Out of Scope

- Automatic integration with any diet or health app
- Weekly/monthly dashboards
- Weight tracking, photos, or body fat
- Automated dietary recommendation system
- Full conversational AI
- Audio or image processing
- Native mobile app (web responsive only)

## Risks

- Nutritional estimates may vary and cause frustration if they appear inconsistent
- Heavy dependency on LLMs for food/exercise extraction can increase costs or reduce quality
- Scoring rules are complex and may introduce bugs without clear testing

## Rabbit Holes to Avoid

- Building a custom nutrition database
- Creating a complex interface for manual macro editing
- Working on charts/diagrams/reports before v1
- Over-optimizing calorie accuracy beyond what is necessary for this stage

## Expected Outcome

A tool that acts as a **smart daily journal**: the user logs everything in seconds, understands whether the day was good or bad, and stays consistent.
v1 should deliver clarity, simplicity, and instant usefulness, something very few nutrition apps provide.
