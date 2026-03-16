# UI Design for Research Workspace

## 1. Wireframes (ASCII/Markdown)

### Login / Register
- Top: Logo and title
- Center: Form fields for username and password
- Bottom: Submit button and links for forgot password/register

### Dashboard
- Token Meter: Horizontal bar showing remaining tokens
- Recent Activity: List of recent actions
- Quick Actions: Buttons for common tasks (e.g. New Search, View Corpus)

### Search Page
- Query Input: Text box at the top
- Filters: Dropdowns and checkboxes for refining search
- Results List: Grid format showing paper titles, authors, etc.
- Paper Preview: Modal with abstract and key details

### Paper Detail View
- Metadata: Title, authors, publication date
- Abstract: Short summary displayed prominently
- Actions: Buttons to save to corpus, add note, etc.

### Private Corpus Manager
- List of saved papers: Clickable entries showing title
- Notes Editor: Text area for editing notes
- Import Option: Button to import papers from central repository

### Output Gallery
- Grid of generated outputs (reviews, slides)
- Options for downloading or sharing outputs

### Token Usage History
- Chart: Bar/line graph showing token usage over time
- Breakdown by action: Table showing usage statistics

## 2. Component Architecture
- Main Components:
  - TokenMeter
  - SearchBar
  - ResultsList
  - PaperDetail
  - CorpusList
  - OutputViewer

- State Management with Zustand:
  - Auth Store: For user session management
  - Corpus Store: To manage saved papers
  - Search Store: For current search and results
  - Output Store: For generated outputs

- API Service Layer:
  - Functions to call backend endpoints (getPaper, savePaper, etc.)

## 3. Real-Time Updates
- WebSocket used for agent progress updates on tasks.
- Example Component: ProgressPanel
- Shows loading indicators, messages, and completion statuses.

## 4. Page Routes (Next.js App Router)
- `/` – Landing
- `/login`
- `/register`
- `/dashboard`
- `/search`
- `/papers/[doi]`
- `/corpus`
- `/outputs`
- `/settings`

## 5. User Flow Examples
### Search Example
- User enters search term
- User sees a list of results
- User selects a paper to view details
- User saves paper to corpus

### Literature Review Example
- User requests a literature review
- User sees agent's progress updates via WebSocket
- User receives output when completed

## 6. Initial Project Scaffold
```
/app
  └── (routes)
/components
  └── (reusable UI)
/lib
  └── (API clients, utils)
/store
  └── (Zustand stores)
/public
  └── (assets)
```