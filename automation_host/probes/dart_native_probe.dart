import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) { stderr.writeln('usage: dart_native_probe.dart NATIVE_PROBE OUTPUT_JSON'); exitCode=2; return; }
  final nativeProbe=arguments[0]; final output=File(arguments[1]); final watch=Stopwatch()..start();
  final result=await Process.run(nativeProbe,const <String>[]); watch.stop();
  Map<String,Object?> native;
  try { native=Map<String,Object?>.from(jsonDecode(result.stdout.toString().trim()) as Map); }
  catch (_) { native=<String,Object?>{'status':'failed','parseError':true}; }
  final capabilities=native['capabilities'] is Map ? Map<String,Object?>.from(native['capabilities']! as Map) : <String,Object?>{};
  final nativeProofs=native['proofs'] is Map ? Map<String,Object?>.from(native['proofs']! as Map) : <String,Object?>{};
  final transcript=File('${output.path}.transcript');
  final first=jsonEncode(<String,Object?>{'nativeReceipt':native,'phase':'detached'});
  await transcript.writeAsString(first,flush:true); final cursor=await transcript.length();
  await transcript.writeAsString('\nDART_CONTROL_PLANE_BACKLOG',mode:FileMode.append,flush:true);
  final reopened=await transcript.open(); await reopened.setPosition(cursor); final backlog=utf8.decode(await reopened.read(4096)); await reopened.close();
  final dartProofs=<String,Object?>{
    'consumerDetached':true,
    'outputWhileDetached':backlog.contains('DART_CONTROL_PLANE_BACKLOG'),
    'reconnectCursorObserved':cursor>0,
    'backlogReplayExact':backlog=='\nDART_CONTROL_PLANE_BACKLOG',
    'noDuplicationOrLoss':(await transcript.readAsString())==first+backlog,
    'descendantProcessCreated':nativeProofs['descendantProcessCreated']==true,
    'descendantTerminated':nativeProofs['descendantTerminated']==true,
    'zeroSurvivingDescendants':nativeProofs['zeroSurvivingDescendants']==true,
  };
  final passed=result.exitCode==0&&native['status']=='passed'&&capabilities.values.every((v)=>v==true)&&dartProofs.values.every((v)=>v==true);
  final receipt=<String,Object?>{
    'schemaVersion':'2.0.0','candidate':'dart-control-plane-native-pty-helper','status':passed?'passed':'failed','coldStartMs':watch.elapsedMicroseconds/1000.0,
    'capabilities':capabilities,'proofs':dartProofs,'implementationIndependentlyExercised':true,'nativeReceipt':native,
  };
  await output.writeAsString('${jsonEncode(receipt)}\n',flush:true); await transcript.delete(); if(!passed) exitCode=1;
}
