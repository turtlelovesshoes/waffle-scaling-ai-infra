# Use a base image with Python installed
FROM python:3.9-slim-buster

# Set the working directory inside the container
WORKDIR /app

# Copy the HTML files to a designated static content directory
COPY ./static_html/ /app/static/

# Copy the Python application files
COPY ./python_app/ /app/

# Install any Python dependencies
COPY ./python_app/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Expose the port your Python application will listen on
EXPOSE 8000

# Command to run your Python application (e.g., with Gunicorn or Uvicorn)
# This example assumes a Flask app named 'app.py' within 'python_app' folder
# and uses Gunicorn to serve it, potentially serving static files through Flask as well.
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8000", "python_app.app:app"]
