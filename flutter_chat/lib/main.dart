import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image/image.dart' as I;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

final googleSignIn = new GoogleSignIn();
final analytics = new FirebaseAnalytics();
final auth = FirebaseAuth.instance;

void main() => runApp(new MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: 'Flutter Chat',
      theme: new ThemeData(
          primarySwatch: Colors.red,
          textTheme:
              new TextTheme(subhead: new TextStyle(color: Colors.white))),
      home: new ChatScreen(title: 'Flutter Chat'),
    );
  }
}

class ChatScreen extends StatefulWidget {
  ChatScreen({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _ChatScreenState createState() => new _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final reference = FirebaseDatabase.instance.reference().child('messages');

  final TextEditingController _controller = new TextEditingController();

  bool _isComposing = false;

  _ChatScreenState() {
    _ensureLoggedIn();
    reference.onChildAdded.listen((Event event){
      setState((){});
    });
  }

  Future<Null> _ensureLoggedIn() async {
    GoogleSignInAccount user = googleSignIn.currentUser;
    if (user == null) user = await googleSignIn.signInSilently();
    if (user == null) {
      await googleSignIn.signIn();
      analytics.logLogin();
    }
    if (await auth.currentUser() == null) {
      GoogleSignInAuthentication credentials =
          await googleSignIn.currentUser.authentication;
      await auth.signInWithGoogle(
        idToken: credentials.idToken,
        accessToken: credentials.accessToken,
      );
    }
    setState(() {});
  }

  Future<Null> _handleSubmit(String text) async {
    _controller.clear();
    setState(() {
      _isComposing = false;
    });
    await _ensureLoggedIn();
    _sendMessage(text: text);
  }

  void _sendMessage({String text, String imageUrl}) {
    reference.push().set({
      'text': text,
      'imageUrl': imageUrl,
      'senderName': googleSignIn.currentUser.displayName,
      'senderPhotoUrl': googleSignIn.currentUser.photoUrl,
      'email': googleSignIn.currentUser.email
    });
    analytics.logEvent(name: 'send_message');
  }

  Widget _textComposer() {
    return new Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: new Row(
        children: <Widget>[
          new Container(
            margin: new EdgeInsets.symmetric(horizontal: 4.0),
            child: new IconButton(
                icon: new Icon(Icons.photo_camera),
                onPressed: () async {
                  await _ensureLoggedIn();
                  File imageFile = await ImagePicker.pickImage();
                  String timeStamp = new DateTime.now().toIso8601String();
                  await new Future.delayed(new Duration(milliseconds: 500));
                  I.Image _img = I.decodeImage(imageFile.readAsBytesSync());
                  if (_img.width > 720) {
                    _img = I.copyResize(_img, 720);
                  }
                  String dir = (await getTemporaryDirectory()).path;
                  File newImage = new File(dir + timeStamp + ".jpg");
                  newImage.writeAsBytesSync(I.encodeJpg(_img));
                  StorageReference ref = FirebaseStorage.instance
                      .ref()
                      .child("image_" + timeStamp + ".jpg");
                  StorageUploadTask uploadTask = ref.put(newImage);
                  Uri downloadUrl = (await uploadTask.future).downloadUrl;
                  newImage.deleteSync();
                  _sendMessage(imageUrl: downloadUrl.toString());
                }),
          ),
          new Flexible(
              child: new TextField(
            controller: _controller,
            style: Theme.of(context).textTheme.subhead.copyWith(color: Colors.black),
            onChanged: (String text) => setState(() {
                  _isComposing = text.length > 0;
                }),
            onSubmitted: _handleSubmit,
            decoration:
                new InputDecoration.collapsed(hintText: "Start typing..."),
          )),
          new IconButton(
            icon: new Icon(Icons.send),
            onPressed:
                _isComposing ? () => _handleSubmit(_controller.text) : null,
            color: Theme.of(context).accentColor,
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text(widget.title),
      ),
      body: new Center(
        child: new Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            new Flexible(
                child: new FirebaseAnimatedList(
              query: reference,
              sort: (a, b) => b.key.compareTo(a.key),
              padding: new EdgeInsets.all(8.0),
              reverse: true,
              itemBuilder:
                  (_, DataSnapshot snapshot, Animation<double> animation) {
                return googleSignIn.currentUser == null
                    ? new Container()
                    : new Message(snapshot: snapshot, animation: animation);
              },
            )),
            const Divider(
              height: 1.0,
            ),
            _textComposer()
          ],
        ),
      ),
    );
  }
}

class Message extends StatelessWidget {
  final DataSnapshot snapshot;
  final Animation animation;

  Message({this.snapshot, this.animation});

  @override
  Widget build(BuildContext context) {
    return new SizeTransition(
      sizeFactor: new CurvedAnimation(parent: animation, curve: Curves.easeOut),
      axisAlignment: 0.0,
      child: new Container(
        margin: new EdgeInsets.only(
            left: googleSignIn.currentUser.email == snapshot.value['email']
                ? 25.0
                : 0.0,
            right: googleSignIn.currentUser.email == snapshot.value['email']
                ? 0.0
                : 25.0,
            top: 5.0,
            bottom: 5.0),
        padding: const EdgeInsets.all(10.0),
        decoration: new BoxDecoration(
            color: Theme.of(context).primaryColor,
            border: new Border(),
            borderRadius: new BorderRadius.only(
                bottomLeft: new Radius.circular(15.0),
                bottomRight: new Radius.circular(15.0),
                topLeft:
                    googleSignIn.currentUser.email == snapshot.value['email']
                        ? new Radius.circular(15.0)
                        : Radius.zero,
                topRight:
                    googleSignIn.currentUser.email == snapshot.value['email']
                        ? Radius.zero
                        : new Radius.circular(15.0))),
        child: new Row(
          mainAxisAlignment:
              googleSignIn.currentUser.email == snapshot.value['email']
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            new Container(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: new CircleAvatar(
                backgroundImage:
                    new NetworkImage(snapshot.value['senderPhotoUrl']),
              ),
            ),
            new Flexible(
                child: new Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                new Text(snapshot.value['senderName'] + ":",
                    style: Theme
                        .of(context)
                        .textTheme
                        .subhead
                        .copyWith(fontWeight: FontWeight.bold)),
                new Container(
                  margin: const EdgeInsets.only(top: 5.0),
                  width: MediaQuery.of(context).size.width * 0.7,
                  child: snapshot.value['imageUrl'] != null
                      ? new Stack(
                          children: <Widget>[
                            const SizedBox(
                              child: const LinearProgressIndicator(),
                              height: 2.0,
                            ),
                            new InkResponse(
                              child: new Hero(tag: snapshot.value["imageUrl"], child: new Image(
                                  image: new CachedNetworkImageProvider(
                                      snapshot.value["imageUrl"]))),onTap: () => Navigator.of(context).push(new MaterialPageRoute(builder: (BuildContext context){
                                        return new ViewImage(url: snapshot.value["imageUrl"],);
                            })),
                            ),
                          ],
                        )
                      : new Text(
                          snapshot.value['text'],
                        ),
                ),
              ],
            ))
          ],
        ),
      ),
    );
  }
}

class ViewImage extends StatelessWidget {

  final String url;

  ViewImage({this.url});

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text("Image"),
      ),
      body: new Center(
        child: new Hero(tag: url, child: new Image(image: new CachedNetworkImageProvider(url))),
      ),
    );
  }
}

