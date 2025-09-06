# Day 10 - Treasure Island - Python Code
# https://www.udemy.com/course/the-complete-2024-web-development-bootcamp
# TOFO please make freinly ui and demo video in youtube. 
import time, os
def game_over():
    print(r'''
       _____                         ____                 
      / ____|                       / __ \                
     | |  __  __ _ _ __ ___   ___  | |  | |_   _____ _ __ 
     | | |_ |/ _` | '_ ` _ \ / _ \ | |  | \ \ / / _ \ '__|
     | |__| | (_| | | | | | |  __/ | |__| |\ V /  __/ |   
      \_____|\__,_|_| |_| |_|\___|  \____/  \_/ \___|_|   

                         G A M E   O V E R
    ''')
    input("Press Enter to continue...")  # Pause before restarting
    time.sleep(5) #or clear screen here
def you_win():
    print(r'''
        
    
    __   __           __        ___       _ 
    \ \ / /__  _   _  \ \      / (_)_ __ | |
     \ V / _ \| | | |  \ \ /\ / /| | '_ \| |
      | | (_) | |_| |   \ V  V / | | | | |_|
      |_|\___/ \__,_|    \_/\_/  |_|_| |_(_)
    

    ''' )
    input("Press Enter to continue...")  # Pause before restarting
    time.sleep(5)  # or clear screen here



while True:
    print(r'''
*******************************************************************************
          |                   |                  |                     |
 _________|________________.=""_;=.______________|_____________________|_______
|                   |  ,-"_,=""     `"=.|                  |
|___________________|__"=._o`"-._        `"=.______________|___________________
          |                `"=._o`"=._      _`"=._                     |
 _________|_____________________:=._o "=._."_.-="'"=.__________________|_______
|                   |    __.--" , ; `"=._o." ,-"""-._ ".   |
|___________________|_._"  ,. .` ` `` ,  `"-._"-._   ". '__|___________________
          |           |o`"=._` , "` `; .". ,  "-._"-._; ;              |
 _________|___________| ;`-.o`"=._; ." ` '`."\ ` . "-._ /_______________|_______
|                   | |o ;    `"-.o`"=._``  '` " ,__.--o;   |
|___________________|_| ;     (#) `-.o `"=.`_.--"_o.-; ;___|___________________
____/______/______/___|o;._    "      `".o|o_.--"    ;o;____/______/______/____
/______/______/______/_"=._o--._        ; | ;        ; ;/______/______/______/_
____/______/______/______/__"=._o--._   ;o|o;     _._;o;____/______/______/____
/______/______/______/______/____"=._o._; | ;_.--"o.--"_/______/______/______/_
____/______/______/______/______/_____"=.o|o_.--""___/______/______/______/____
/______/______/______/______/______/______/______/______/______/______/_____ /
*******************************************************************************
''')
    print("Welcome to Treasure Island.")
    print("Your mission is to find the treasure.")

    # Direction choice
    print(r'''
     _______
    /       \
   |  LEFT   |-----> L
   |         |
   |  RIGHT  |-----> R
    \_______/
    ''')
    direction = input("Do you go L or R? (Type L for left, or R for right): ")

    if direction == "L":
        # Swim or wait
        print(r'''
    ~~~~~    ~~~~~
  ~      ~~~~     ~
 ~  WATER AHEAD  ~~~
 ~    Swim (S)   ~
 ~    or Wait(W) ~
  ~             ~
    ~~~~~    ~~~~~
        ''')
        sw = input("Do you swim or wait? (Type S for swim or W for wait): ")
        if sw == "S":
            print(r'''
               ,--.
           ,--/  /
          /     (
         /       \    
    ____/___(*)___\____
   <_________o_________>  <<<<< ATTACKED BY TROUT!
       \_/     \_/
    ''')
            print("Attacked by trout. Game Over!")
            game_over()
        elif sw == "W":
            # Choose door
            print(r'''
   You arrive at a house with 3 doors:

      _______     _______     _______
     | RED   |   | BLUE  |   | YELLOW|
     |_______|   |_______|   |_______|

     R for Red, B for Blue, Y for Yellow
            ''')
            door = input("Which door do you enter? (R/B/Y or anything else for other): ")

            if door == "R":
                print(r'''
        (  .      )
     )           (              )
           .    '   .   '  .  '  .
    (    , )       (.   )  (   ',    )
     .' ) ( . )    ,  ( ,     )   ( .
  ). , ( .   (  ) ( , ')  .' (  ,    )
 ( . ) ( , ')  .' ) ( , ')  (   )     <<< BURNED BY FIRE!
 ''')
                print("Burned by fire. Game Over!")
                game_over()
            elif door == "B":
                print(r'''
                 .--.   .-"      "-.   .--.
                / .. \/  .-.  .-.  \ / .. \
               | |  '|  /   \/   \  |'  | |
               \ \__/ \_\_/\__/ /__/  / /
                '.__.'\__/\__/|__.'--'
              <<< EATEN BY BEASTS! >>>
                ''')
                print("Eaten by Beasts. Game Over!")
                game_over()
            elif door == "Y":
                print(r'''
        !!! YOU WIN THE TREASURE !!!
                ''')
                you_win()
                break
            else:
                print("Game Over!")
                game_over()

    elif direction == "R":
        print(r'''
        _______
       /       \
      |  HOLE!  |
       \_______/
          ||||
        \====/
         \__/
        <<< You fell into a hole! >>>
        ''')
        print("You fall into a hole. Game Over!")
        game_over()
