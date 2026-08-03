import os,sys
limit=int(os.environ.get('KRISTIN_FIXTURE_BYTES','1048576'))
sys.stdout.buffer.write(b'A'*limit);sys.stderr.buffer.write(b'B'*limit)
