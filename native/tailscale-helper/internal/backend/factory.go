package backend

var defaultFactory Factory = func() Backend { return NewFake() }

func SetDefaultFactory(f Factory) {
	if f != nil {
		defaultFactory = f
	}
}

func DefaultFactory() Factory {
	return defaultFactory
}
