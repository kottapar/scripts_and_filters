# logstash_filters
We've started using ELK stack to gather logs from our Unix environment for analysis. Our setup is a mix of AIX and Linux and so we've got
some unique challenges while trying to centralize the logs.

The idea to share the filters came after I stumbled across this reddit https://www.reddit.com/r/vmware/comments/6bvrg3/anyone_send_syslogs_to_an_elk_stack/

So the first file is going to be the sexilog esxi filter that I've downloaded and tweaked to suit our requirements.
