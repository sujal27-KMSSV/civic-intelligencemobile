# Civic Intelligence

Civic Intelligence is an AI-powered platform for reporting, analyzing and managing urban infrastructure problems.

The idea is simple: instead of treating every citizen complaint as an isolated ticket, the system uses the information from multiple reports to identify the actual issue, estimate its severity, detect possible duplicates and help authorities decide what needs attention first.

The project was developed as a hackathon prototype under the **Smart Cities & Urban Innovation** theme.

## What it does

A citizen can report an issue by providing a photo, description and location.

The system then processes the report and can:

* Identify the type of civic issue
* Estimate its severity
* Generate an AI-based summary
* Assign a priority score
* Find potentially duplicate reports
* Group reports around the same location
* Display issues on a map
* Provide authorities with a prioritized list of problems

### Example

Instead of having five separate complaints:

```text
Report #101 - Large pothole near Sector 62
Report #107 - Road damaged near Sector 62
Report #113 - Big pothole near the intersection
Report #118 - Vehicles swerving around damaged road
```

the platform can recognize that these reports may refer to the same underlying problem.

```text
                 CIVIC INTELLIGENCE
                         |
                         v
                  One actual issue
                         |
              +----------+----------+
              |                     |
        4 supporting reports     High priority
```

This helps reduce duplicate work and gives authorities a clearer picture of what is happening on the ground.

---

## Main Features

### Citizen App

* User login / guest access
* Report a civic issue
* Upload an image
* Add description
* Capture/select location
* View submitted reports
* View nearby issues
* Track issue status

### AI Analysis

Submitted reports can be analyzed for:

* Issue category
* Severity
* Confidence
* Short description/summary
* Recommended action
* Priority

Possible categories include:

* Potholes / road damage
* Garbage
* Broken streetlights
* Water leakage
* Drainage problems
* Other infrastructure issues

### Duplicate Detection

Reports can be compared using a combination of:

* Image similarity
* Text similarity
* Geographic distance

The goal is to determine whether several reports are likely describing the same physical problem.

### Authority Dashboard

Authorities can view:

* Total reported issues
* Critical/high-priority issues
* Pending and resolved issues
* Issue categories
* Civic hotspots
* Individual issue details
* Location-based reports
* AI-generated priority information

### Map & Hotspots

Reports can be displayed geographically to identify areas where civic problems are concentrated.

This can help move from individual complaint handling towards area-level decision making.

---

## How the system works

```text
Citizen
   |
   v
Report + Image + Location
   |
   v
Backend API
   |
   +----------------------+
   |                      |
   v                      v
Database              AI Analysis
   |                      |
   |              +-------+-------+
   |              |       |       |
   |             Type  Severity  Summary
   |                      |
   |                 Priority Score
   |                      |
   +----------+-----------+
              |
              v
       Duplicate Detection
              |
              v
       Authority Dashboard
              |
              v
       Action / Resolution
```

---

## Technology Stack

### Frontend

**Flutter / Dart**

Used to build the cross-platform mobile application for citizens and authorities.

### Backend

**Python / FastAPI**

Provides the REST API and handles communication between the mobile application, database and AI services.

### Database

**PostgreSQL**

Stores users, reports, issue status, categories, locations and other application data.

**PostGIS**

Adds geospatial capabilities to PostgreSQL and is used for location-based operations such as finding nearby reports.

### AI / Machine Learning

**Computer Vision**

Used for analyzing uploaded images and identifying infrastructure problems.

**YOLO**

Can be used for object/problem detection in images.

**OpenCV**

Used for image processing and preprocessing.

**LLM / Vision API**

Used for tasks such as classification, summaries, recommendations and structured analysis.

**CLIP / Embeddings**

Can be used to compare images and identify visually similar reports.

**Cosine Similarity**

Used to measure similarity between generated embeddings.

### Maps

Google Maps / Mapbox / OpenStreetMap can be used for displaying report locations and civic hotspots.

### Storage

Cloud storage such as Cloudinary or Supabase Storage can be used for uploaded images.

### Development

* Git
* GitHub
* OpenCode
* VS Code
* Android Studio
* Postman

---

## Project Structure

The exact structure may change during development, but the project is organized roughly around the following components:

```text
civic-intelligence/
│
├── mobile/
│   └── Flutter application
│
├── backend/
│   ├── API
│   ├── models
│   ├── services
│   └── AI integration
│
├── ai/
│   ├── image analysis
│   ├── similarity
│   └── prioritization
│
├── docs/
│   └── project documentation
│
└── README.md
```

---

## Running the Project

### Requirements

Make sure you have the following installed:

* Flutter
* Dart
* Python 3.x
* Git
* Android Studio (for Android development)
* PostgreSQL, if running the database locally

### Frontend

```bash
cd mobile
flutter pub get
flutter run
```

### Backend

```bash
cd backend

python -m venv venv
```

Activate the virtual environment and install the dependencies:

```bash
pip install -r requirements.txt
```

Start the API:

```bash
uvicorn main:app --reload
```

The exact commands may vary depending on the current project structure.

---

## API Overview

Some of the main API operations include:

```text
POST   /issues
GET    /issues
GET    /issues/{id}
PATCH  /issues/{id}

POST   /ai/analyze
```

The API is responsible for receiving reports, retrieving issue data, updating status and communicating with the AI layer.

---

## Priority System

The platform can combine several factors to determine how urgently an issue should be handled.

For example:

```text
Severity
   +
Number of reports
   +
Location
   +
Duplicate/supporting reports
   +
Potential impact
        |
        v
  Priority Score
```

A critical road hazard with several supporting reports can therefore be placed ahead of a low-impact issue with only one report.

---

## Future Scope

The current project is a hackathon-focused MVP. Possible future improvements include:

* Real-time authority notifications
* More infrastructure categories
* Better image-based detection
* Historical trend analysis
* Predictive identification of civic hotspots
* Integration with municipal systems
* Automatic department routing
* Before/after verification of completed work
* City-wide analytics
* Multi-city deployment
* IoT and CCTV data integration

The longer-term goal is to move from simply collecting complaints to providing authorities with useful, continuously updated information about the condition of a city.

---

## Project Status

**Hackathon Prototype / MVP**

The project is currently focused on demonstrating the core reporting → AI analysis → prioritization → authority workflow.

Some components may use mock data or external AI services for demonstration purposes.

---

## Team

Developed for a hackathon under the **Smart Cities & Urban Innovation** theme.

---

## License

This project is currently intended for educational and hackathon purposes.

