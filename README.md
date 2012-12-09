Everybody needs a cleaning schedule. At work, at home, you name it. But don't try to print it out on a piece of paper. Do it using Campfire, checking who's online and giving all chores a certain amound of points. And the people who has the least amound of points, will be doing the task.

So you know, you can create your own schedule (and it doesn't need to be cleaning chores persee). But it does require somethings, like [Hubot](http://hubot.github.com/).

![Screenshot](http://cl.ly/image/2J1R0a0P1002/content)

## Try it out

First add the roomnumber it should set as 'main' room (uses these users and will message the person that needs to do something from the schedule). Then create your own schedule, by creating an array with items, that require a todo (method) and certain amount of points.

    schedule[5]['17:30'] =
      todo: (user) ->
        "Hey #{user}, get me a beer!"
      points: 1

## Want more?
Please contact me on [Twitter](http://twitter.com/davidvanleeuwen) or check out my website [David van Leeuwen](http://davidvanleeuwen.nl).