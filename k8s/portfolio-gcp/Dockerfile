# Use a base image with Python installed
FROM python:3.9-slim-buster

# Set the working directory inside the container
WORKDIR /app

# Copy the Python application files
# The contents of ./python_app/ will be copied directly into /app/
COPY ./python_app/ /app/

# Copy the HTML files to a designated static content directory
# Assuming the Flask app is configured to serve static files from /app/static/
COPY ./static_html/ /app/static/

# Install any Python dependencies
COPY ./python_app/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Expose the port your Python application will listen on
EXPOSE 8080

# Command to run your Python application with Gunicorn
# 'app:app' refers to the 'app' variable inside 'app.py'
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8080", "app:app"]