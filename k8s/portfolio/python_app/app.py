from flask import Flask, render_template

app = Flask(__name__, template_folder='static_html')

@app.route('/')
def project():
    print("Hello and Welcome to My Website! These first few questions are to generate your code name for the site as you visit!")
    name = input("Please share your name: (type then hit enter)  ")
    like = input("Please share the name of a person you like: ")
    pet =  input("Please give the name of your Pet or your favorite cartoon character: ")
    print("While you are here, we will call you: " + pet + " " + like + "! Welcome!")
    return render_template('project.html')

if __name__ == '__main__':
    app.run()