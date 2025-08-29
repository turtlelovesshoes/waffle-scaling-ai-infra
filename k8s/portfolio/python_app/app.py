import os
from flask import Flask, render_template, request

app = Flask(
    __name__, 
    template_folder=os.path.join(os.path.dirname(os.path.abspath(__file__)), '../static_html')
)

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
if __name__ == '__main__':
    app.run()