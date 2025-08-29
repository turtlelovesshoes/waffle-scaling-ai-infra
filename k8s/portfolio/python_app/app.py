import os
from datetime import datetime
from flask import Flask, render_template, request
from flask_sqlalchemy import SQLAlchemy

class Config:
    """Base configuration class"""
    SECRET_KEY = os.environ.get('SECRET_KEY', 'your-secret-key')
    SQLALCHEMY_TRACK_MODIFICATIONS = False

class DevelopmentConfig(Config):
    """Development configuration for local testing with SQLite"""
    SQLALCHEMY_DATABASE_URI = 'sqlite:///blog.db'  # Local SQLite database

class ProductionConfig(Config):
    """Production configuration for cloud with PostgreSQL"""
    SQLALCHEMY_DATABASE_URI = os.environ.get('CLOUD_DB_URI', 'postgresql://user:pass@host:port/db')  # Cloud DB URI (Postgres)


# ------------------------------
# App & DB Configuration
# ------------------------------
app = Flask(
    __name__,
    template_folder=os.path.join(os.path.dirname(os.path.abspath(__file__)), '../static_html')
)
# Local/cloud detection
#if os.environ.get('FLASK_ENV') == 'local':
    # Use SQLite locally
#    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///blog.db'
#else:
#    # Use cloud Postgres (replace with your real URI)
#    app.config['SQLALCHEMY_DATABASE_URI'] = 'postgresql://user:pass@host:port/db'
app.config.from_object(DevelopmentConfig)

app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# ------------------------------./ 
# Models
# ------------------------------
class BlogPost(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(100), nullable=False)
    content = db.Column(db.Text, nullable=False)
    date_posted = db.Column(db.DateTime, default=datetime.utcnow)

# ------------------------------
# Initialize local DB & seed
# ------------------------------
if app.config['SQLALCHEMY_DATABASE_URI'].startswith('sqlite'):
    with app.app_context():
        db.create_all()
        # Seed sample post if empty
        if BlogPost.query.count() == 0:
            sample = BlogPost(
                title="Hello World",
                content="This is your first blog post!"
            )
            db.session.add(sample)
            db.session.commit()

# ------------------------------
# Routes
# ------------------------------
@app.route('/')
def project():
    return render_template('project.html')


@app.route('/name_generator', methods=['GET', 'POST'])
def name_generator():
    if request.method == 'POST':
        name = request.form.get('name')
        like = request.form.get('like')
        pet = request.form.get('pet')
        code_name = f"{pet} {like}"
        return render_template('name_generator.html', code_name=code_name, name=name)
    return render_template('name_generator.html')


@app.route('/blog')
def blog():
    posts = BlogPost.query.order_by(BlogPost.date_posted.desc()).all()
    return render_template('blog.html', posts=posts)

# ------------------------------
# Run App
# ------------------------------
if __name__ == '__main__':
    app.run(debug=True)
